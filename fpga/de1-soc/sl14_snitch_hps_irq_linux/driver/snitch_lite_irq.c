#include <linux/fs.h>
#include <linux/init.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/irq.h>
#include <linux/irqdomain.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_irq.h>
#include <linux/poll.h>
#include <linux/sched.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <linux/wait.h>

#define SNITCH_IRQ_PENDING_DEFAULT 0x3cu
#define SNITCH_IRQ_STATUS_PENDING  BIT(0)
#define SNITCH_IRQ_STATUS_LINE     BIT(2)

struct snitch_irq_event {
	u32 count;
	u32 status;
};

static int irq = 72;
static int gic_spi = -1;
static int gic_hwirq = -1;
static unsigned long mmio_base = 0xff200000ul;
static unsigned long mmio_size = 0x1000ul;
static unsigned int irq_pending_offset = SNITCH_IRQ_PENDING_DEFAULT;
static int requested_irq;
static bool requested_irq_is_mapping;

module_param(irq, int, 0444);
MODULE_PARM_DESC(irq, "Linux virtual IRQ number for legacy kernels");
module_param(gic_spi, int, 0444);
MODULE_PARM_DESC(gic_spi, "GIC SPI number for f2h_irq0 bit 0; Cyclone V uses SPI 40");
module_param(gic_hwirq, int, 0444);
MODULE_PARM_DESC(gic_hwirq, "GIC hwirq for f2h_irq0 bit 0; Cyclone V uses 72");
module_param(mmio_base, ulong, 0444);
MODULE_PARM_DESC(mmio_base, "Snitch-Lite lightweight HPS-to-FPGA MMIO base");
module_param(mmio_size, ulong, 0444);
MODULE_PARM_DESC(mmio_size, "Snitch-Lite MMIO span");
module_param(irq_pending_offset, uint, 0444);
MODULE_PARM_DESC(irq_pending_offset, "Snitch-Lite IRQ pending register offset");

static void __iomem *regs;
static DECLARE_WAIT_QUEUE_HEAD(snitch_irq_waitq);
static atomic_t event_count = ATOMIC_INIT(0);
static u32 last_status;
static DEFINE_SPINLOCK(last_status_lock);

static inline u32 snitch_irq_read_pending(void)
{
	return readl(regs + irq_pending_offset);
}

static inline void snitch_irq_ack_pending(void)
{
	writel(SNITCH_IRQ_STATUS_PENDING, regs + irq_pending_offset);
}

static irqreturn_t snitch_lite_irq_handler(int irq_num, void *dev_id)
{
	unsigned long flags;
	u32 status = snitch_irq_read_pending();

	if ((status & (SNITCH_IRQ_STATUS_PENDING | SNITCH_IRQ_STATUS_LINE)) == 0)
		return IRQ_NONE;

	snitch_irq_ack_pending();

	spin_lock_irqsave(&last_status_lock, flags);
	last_status = status;
	atomic_inc(&event_count);
	spin_unlock_irqrestore(&last_status_lock, flags);

	wake_up_interruptible(&snitch_irq_waitq);
	return IRQ_HANDLED;
}

static int snitch_lite_irq_open(struct inode *inode, struct file *file)
{
	file->private_data = (void *)(unsigned long)atomic_read(&event_count);
	return nonseekable_open(inode, file);
}

static ssize_t snitch_lite_irq_read(struct file *file, char __user *buf,
				    size_t len, loff_t *ppos)
{
	struct snitch_irq_event event;
	unsigned int seen = (unsigned long)file->private_data;
	unsigned long flags;
	int ret;

	if (len < sizeof(event))
		return -EINVAL;

	ret = wait_event_interruptible(snitch_irq_waitq,
				       atomic_read(&event_count) != seen);
	if (ret)
		return ret;

	event.count = atomic_read(&event_count);

	spin_lock_irqsave(&last_status_lock, flags);
	event.status = last_status;
	spin_unlock_irqrestore(&last_status_lock, flags);

	file->private_data = (void *)(unsigned long)event.count;

	if (copy_to_user(buf, &event, sizeof(event)))
		return -EFAULT;

	return sizeof(event);
}

static unsigned int snitch_lite_irq_poll(struct file *file, poll_table *wait)
{
	unsigned int seen = (unsigned long)file->private_data;

	poll_wait(file, &snitch_irq_waitq, wait);
	if (atomic_read(&event_count) != seen)
		return POLLIN | POLLRDNORM;

	return 0;
}

static const struct file_operations snitch_lite_irq_fops = {
	.owner = THIS_MODULE,
	.open = snitch_lite_irq_open,
	.read = snitch_lite_irq_read,
	.poll = snitch_lite_irq_poll,
	.llseek = no_llseek,
};

static struct miscdevice snitch_lite_irq_miscdev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "snitch_lite_irq",
	.fops = &snitch_lite_irq_fops,
};

static int snitch_lite_resolve_irq(void)
{
	struct device_node *gic_np;
	struct irq_domain *domain;
	struct of_phandle_args irq_data;
	unsigned int virq;

	if (gic_spi < 0 && gic_hwirq < 0) {
		requested_irq = irq;
		requested_irq_is_mapping = false;
		pr_info("snitch_lite_irq: using legacy Linux irq=%d\n", requested_irq);
		return 0;
	}

	gic_np = of_find_compatible_node(NULL, NULL, "arm,cortex-a9-gic");
	if (!gic_np)
		gic_np = of_find_compatible_node(NULL, NULL, "arm,gic-400");
	if (!gic_np)
		return -ENODEV;

	if (gic_spi >= 0) {
		irq_data.np = gic_np;
		irq_data.args_count = 3;
		irq_data.args[0] = 0; /* SPI */
		irq_data.args[1] = gic_spi;
		irq_data.args[2] = IRQ_TYPE_LEVEL_HIGH;

		virq = irq_create_of_mapping(&irq_data);
		of_node_put(gic_np);
		if (!virq)
			return -EINVAL;

		requested_irq = virq;
		requested_irq_is_mapping = true;
		pr_info("snitch_lite_irq: mapped GIC SPI %d to Linux irq=%d\n",
			gic_spi, requested_irq);
		return 0;
	}

	domain = irq_find_host(gic_np);
	of_node_put(gic_np);
	if (!domain)
		return -ENODEV;

	virq = irq_create_mapping(domain, (irq_hw_number_t)gic_hwirq);
	if (!virq)
		return -EINVAL;

	requested_irq = virq;
	requested_irq_is_mapping = true;
	pr_info("snitch_lite_irq: mapped GIC hwirq %d to Linux irq=%d\n",
		gic_hwirq, requested_irq);
	return 0;
}

static int __init snitch_lite_irq_init(void)
{
	int ret;

	if (irq_pending_offset + sizeof(u32) > mmio_size)
		return -EINVAL;

	regs = ioremap(mmio_base, mmio_size);
	if (!regs)
		return -ENOMEM;

	snitch_irq_ack_pending();

	ret = snitch_lite_resolve_irq();
	if (ret)
		goto err_iounmap;

	ret = irq_set_irq_type(requested_irq, IRQ_TYPE_LEVEL_HIGH);
	if (ret)
		pr_warn("snitch_lite_irq: irq_set_irq_type(%d) returned %d\n",
			requested_irq, ret);

	ret = request_irq(requested_irq, snitch_lite_irq_handler, IRQF_TRIGGER_HIGH,
			  "snitch_lite_irq", &snitch_lite_irq_miscdev);
	if (ret) {
		if (requested_irq_is_mapping)
			irq_dispose_mapping(requested_irq);
		goto err_iounmap;
	}

	ret = misc_register(&snitch_lite_irq_miscdev);
	if (ret)
		goto err_free_irq;

	pr_info("snitch_lite_irq: irq=%d gic_spi=%d gic_hwirq=%d mmio=0x%lx size=0x%lx pending=0x%x\n",
		requested_irq, gic_spi, gic_hwirq, mmio_base, mmio_size,
		irq_pending_offset);
	return 0;

err_free_irq:
	free_irq(requested_irq, &snitch_lite_irq_miscdev);
	if (requested_irq_is_mapping)
		irq_dispose_mapping(requested_irq);
err_iounmap:
	iounmap(regs);
	regs = NULL;
	return ret;
}

static void __exit snitch_lite_irq_exit(void)
{
	misc_deregister(&snitch_lite_irq_miscdev);
	free_irq(requested_irq, &snitch_lite_irq_miscdev);
	if (requested_irq_is_mapping)
		irq_dispose_mapping(requested_irq);
	if (regs) {
		snitch_irq_ack_pending();
		iounmap(regs);
	}
	pr_info("snitch_lite_irq: unloaded\n");
}

module_init(snitch_lite_irq_init);
module_exit(snitch_lite_irq_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("hero-tools educational bring-up");
MODULE_DESCRIPTION("Snitch-Lite DE1-SoC FPGA-to-HPS IRQ waiter");
