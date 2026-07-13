#include <linux/delay.h>
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/interrupt.h>
#include <linux/io.h>
#include <linux/irq.h>
#include <linux/irqdomain.h>
#include <linux/jiffies.h>
#include <linux/miscdevice.h>
#include <linux/module.h>
#include <linux/mutex.h>
#include <linux/of.h>
#include <linux/of_irq.h>
#include <linux/slab.h>
#include <linux/uaccess.h>
#include <linux/wait.h>

#include "h6_job_api.h"

#define H6_MMIO_BASE_DEFAULT 0xff200000ul
#define H6_MMIO_SIZE 0x3000ul
#define H6_BLOCK_ID 0x48300005u

#define H6_REG_ID 0x00
#define H6_REG_CONTROL 0x04
#define H6_REG_STATUS 0x08
#define H6_REG_RESULT 0x10
#define H6_REG_IRQ_ENABLE 0x14
#define H6_REG_IRQ_PENDING 0x18
#define H6_REG_BOOT_BASE 0x1c
#define H6_REG_BOOT_SIZE 0x20
#define H6_REG_DATA_BASE 0x24
#define H6_REG_DATA_SIZE 0x28
#define H6_REG_JOB_DOORBELL 0x2c

#define H6_BOOT_OFFSET 0x1000
#define H6_BOOT_BYTES 4096
#define H6_DATA_OFFSET 0x2000
#define H6_DATA_BYTES 4096
#define H6_STATUS_RESULT_VALID BIT(4)
#define H6_IRQ_PENDING BIT(0)
#define H6_IRQ_LINE BIT(2)
#define H7_JOB_ACTIVE BIT(0)
#define H7_HOST_ACCESS BIT(2)

#define H4_MAGIC 0x48344a42u
#define H4_VERSION 1u
#define H4_STATE_READY 1u
#define H4_STATE_DONE 3u
#define H4_STATUS_OK 0u
#define H4_COMPLETION 0x4834u
#define H4_DESC_MAGIC 0x00
#define H4_DESC_VERSION 0x04
#define H4_DESC_STATE 0x08
#define H4_DESC_STATUS 0x0c
#define H4_DESC_COUNT 0x10
#define H4_DESC_INPUT_OFFSET 0x14
#define H4_DESC_OUTPUT_OFFSET 0x18
#define H4_DESC_MULTIPLIER 0x1c
#define H4_DESC_BIAS 0x20
#define H4_INPUT_OFFSET 0x100
#define H4_OUTPUT_OFFSET 0x200

static int irq = 72;
static int gic_spi = -1;
static int gic_hwirq = -1;
static unsigned long mmio_base = H6_MMIO_BASE_DEFAULT;
static int requested_irq;
static bool requested_irq_is_mapping;
static void __iomem *regs;
static atomic_t event_count = ATOMIC_INIT(0);
static atomic_t open_count = ATOMIC_INIT(0);
static DECLARE_WAIT_QUEUE_HEAD(job_waitq);
static DEFINE_MUTEX(job_lock);
static bool program_loaded;
static bool resident_mode;
static bool worker_started;
static unsigned int worker_start_count;

module_param(irq, int, 0444);
MODULE_PARM_DESC(irq, "Linux virtual IRQ number for legacy kernels");
module_param(gic_spi, int, 0444);
MODULE_PARM_DESC(gic_spi, "GIC SPI number; Cyclone V f2h_irq0 bit 0 uses 40");
module_param(gic_hwirq, int, 0444);
MODULE_PARM_DESC(gic_hwirq, "GIC hardware IRQ; Cyclone V f2h_irq0 bit 0 uses 72");
module_param(mmio_base, ulong, 0444);
MODULE_PARM_DESC(mmio_base, "HPS lightweight bridge physical base");
module_param(resident_mode, bool, 0444);
MODULE_PARM_DESC(resident_mode, "Keep the Snitch worker resident and submit through H7 doorbell");

static inline void h6_write(u32 offset, u32 value)
{
	writel(value, regs + offset);
}

static inline u32 h6_read(u32 offset)
{
	return readl(regs + offset);
}

static int h6_wait_result_clear(void)
{
	unsigned int i;

	for (i = 0; i < 1000000; ++i) {
		if (!(h6_read(H6_REG_STATUS) & H6_STATUS_RESULT_VALID))
			return 0;
		udelay(1);
	}
	return -ETIMEDOUT;
}

static int h7_wait_job_idle(void)
{
	unsigned int i;
	u32 state;

	for (i = 0; i < 1000000; ++i) {
		state = h6_read(H6_REG_JOB_DOORBELL);
		if (!(state & H7_JOB_ACTIVE) && (state & H7_HOST_ACCESS))
			return 0;
		udelay(1);
	}
	return -ETIMEDOUT;
}

static irqreturn_t h6_irq_handler(int irq_num, void *dev_id)
{
	u32 status = h6_read(H6_REG_IRQ_PENDING);

	if (!(status & (H6_IRQ_PENDING | H6_IRQ_LINE)))
		return IRQ_NONE;
	h6_write(H6_REG_IRQ_PENDING, H6_IRQ_PENDING);
	atomic_inc(&event_count);
	wake_up_interruptible(&job_waitq);
	return IRQ_HANDLED;
}

static int h6_open(struct inode *inode, struct file *file)
{
	if (atomic_cmpxchg(&open_count, 0, 1) != 0)
		return -EBUSY;
	return nonseekable_open(inode, file);
}

static int h6_release(struct inode *inode, struct file *file)
{
	h6_write(H6_REG_CONTROL, 0);
	h6_write(H6_REG_IRQ_ENABLE, 0);
	atomic_set(&open_count, 0);
	return 0;
}

static ssize_t h6_load_program(struct file *file, const char __user *buf,
			       size_t count, loff_t *ppos)
{
	u32 *image;
	unsigned int i;
	int ret;

	if (*ppos != 0)
		return -ESPIPE;
	if (!count || count > H6_BOOT_BYTES || (count & 3))
		return -EINVAL;
	image = kmalloc(count, GFP_KERNEL);
	if (!image)
		return -ENOMEM;
	if (copy_from_user(image, buf, count)) {
		kfree(image);
		return -EFAULT;
	}
	ret = mutex_lock_interruptible(&job_lock);
	if (ret) {
		kfree(image);
		return ret;
	}
	h6_write(H6_REG_CONTROL, 0);
	worker_started = false;
	ret = h6_wait_result_clear();
	if (!ret) {
		for (i = 0; i < count / sizeof(u32); ++i)
			h6_write(H6_BOOT_OFFSET + i * sizeof(u32), image[i]);
		program_loaded = true;
		*ppos += count;
	}
	mutex_unlock(&job_lock);
	kfree(image);
	return ret ? ret : count;
}

static void h6_write_descriptor(const struct h6_job *job)
{
	unsigned int i;
	u32 base = H6_DATA_OFFSET;

	h6_write(base + H4_DESC_MAGIC, H4_MAGIC);
	h6_write(base + H4_DESC_VERSION, H4_VERSION);
	h6_write(base + H4_DESC_STATE, H4_STATE_READY);
	h6_write(base + H4_DESC_STATUS, H4_STATUS_OK);
	h6_write(base + H4_DESC_COUNT, job->count);
	h6_write(base + H4_DESC_INPUT_OFFSET, H4_INPUT_OFFSET);
	h6_write(base + H4_DESC_OUTPUT_OFFSET, H4_OUTPUT_OFFSET);
	h6_write(base + H4_DESC_MULTIPLIER, job->multiplier);
	h6_write(base + H4_DESC_BIAS, job->bias);
	for (i = 0; i < job->count; ++i) {
		h6_write(base + H4_INPUT_OFFSET + i * sizeof(u32), job->input[i]);
		h6_write(base + H4_OUTPUT_OFFSET + i * sizeof(u32), 0);
	}
}

static int h6_run_job(struct h6_job *job)
{
	unsigned int i;
	unsigned int seen;
	long waited;
	int ret;

	if (!program_loaded)
		return -ENODATA;
	if (!job->count || job->count > H6_JOB_MAX_WORDS)
		return -EINVAL;

	if (!resident_mode || !worker_started) {
		h6_write(H6_REG_CONTROL, 0);
		ret = h6_wait_result_clear();
		if (ret)
			return ret;
	} else {
		ret = h7_wait_job_idle();
		if (ret)
			return ret;
	}
	h6_write_descriptor(job);
	h6_write(H6_REG_IRQ_PENDING, H6_IRQ_PENDING);
	h6_write(H6_REG_IRQ_ENABLE, 1);
	seen = atomic_read(&event_count);
	wmb();
	if (resident_mode) {
		if (!worker_started) {
			h6_write(H6_REG_CONTROL, 1);
			worker_started = true;
			++worker_start_count;
		}
		h6_write(H6_REG_JOB_DOORBELL, 1);
	} else {
		h6_write(H6_REG_CONTROL, 1);
	}

	waited = wait_event_interruptible_timeout(job_waitq,
		atomic_read(&event_count) != seen, msecs_to_jiffies(5000));
	if (waited <= 0) {
		ret = waited < 0 ? waited : -ETIMEDOUT;
		goto stop;
	}
	job->completion = h6_read(H6_REG_RESULT);
	job->event_count = atomic_read(&event_count);

stop:
	if (!resident_mode || ret) {
		h6_write(H6_REG_CONTROL, 0);
		worker_started = false;
		if (h6_wait_result_clear() && !ret)
			ret = -ETIMEDOUT;
	} else if (h7_wait_job_idle()) {
		ret = -ETIMEDOUT;
	}
	if (ret)
		return ret;
	job->status = h6_read(H6_DATA_OFFSET + H4_DESC_STATUS);
	if (h6_read(H6_DATA_OFFSET + H4_DESC_STATE) != H4_STATE_DONE ||
	    job->status != H4_STATUS_OK || job->completion != H4_COMPLETION)
		return -EIO;
	for (i = 0; i < job->count; ++i)
		job->output[i] = h6_read(H6_DATA_OFFSET + H4_OUTPUT_OFFSET +
					     i * sizeof(u32));
	job->reserved[0] = worker_start_count;
	job->reserved[1] = resident_mode ? h6_read(H6_REG_JOB_DOORBELL) : 0;
	return 0;
}

static long h6_ioctl(struct file *file, unsigned int command, unsigned long arg)
{
	struct h6_job job;
	int ret;

	if (command != H6_JOB_IOCTL_SUBMIT)
		return -ENOTTY;
	if (copy_from_user(&job, (void __user *)arg, sizeof(job)))
		return -EFAULT;
	ret = mutex_lock_interruptible(&job_lock);
	if (ret)
		return ret;
	ret = h6_run_job(&job);
	mutex_unlock(&job_lock);
	if (ret)
		return ret;
	if (copy_to_user((void __user *)arg, &job, sizeof(job)))
		return -EFAULT;
	return 0;
}

static const struct file_operations h6_fops = {
	.owner = THIS_MODULE,
	.open = h6_open,
	.release = h6_release,
	.write = h6_load_program,
	.unlocked_ioctl = h6_ioctl,
	.llseek = no_llseek,
};

static struct miscdevice h6_miscdev = {
	.minor = MISC_DYNAMIC_MINOR,
	.name = "snitch_job",
	.fops = &h6_fops,
};

static int h6_resolve_irq(void)
{
	struct device_node *gic_np;
	struct irq_domain *domain;
	struct of_phandle_args irq_data;
	unsigned int virq;

	if (gic_spi < 0 && gic_hwirq < 0) {
		requested_irq = irq;
		requested_irq_is_mapping = false;
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
		irq_data.args[0] = 0;
		irq_data.args[1] = gic_spi;
		irq_data.args[2] = IRQ_TYPE_LEVEL_HIGH;
		virq = irq_create_of_mapping(&irq_data);
		of_node_put(gic_np);
		if (!virq)
			return -EINVAL;
		requested_irq = virq;
		requested_irq_is_mapping = true;
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
	return 0;
}

static int __init h6_init(void)
{
	int ret;

	BUILD_BUG_ON(sizeof(struct h6_job) != 0x120);
	regs = ioremap(mmio_base, H6_MMIO_SIZE);
	if (!regs)
		return -ENOMEM;
	if (h6_read(H6_REG_ID) != H6_BLOCK_ID ||
	    h6_read(H6_REG_BOOT_BASE) != H6_BOOT_OFFSET ||
	    h6_read(H6_REG_BOOT_SIZE) != H6_BOOT_BYTES ||
	    h6_read(H6_REG_DATA_BASE) != H6_DATA_OFFSET ||
	    h6_read(H6_REG_DATA_SIZE) != H6_DATA_BYTES) {
		ret = -ENODEV;
		goto err_unmap;
	}
	if (resident_mode && !(h6_read(H6_REG_JOB_DOORBELL) & H7_HOST_ACCESS)) {
		ret = -ENODEV;
		goto err_unmap;
	}
	h6_write(H6_REG_CONTROL, 0);
	h6_write(H6_REG_IRQ_ENABLE, 0);
	h6_write(H6_REG_IRQ_PENDING, H6_IRQ_PENDING);
	ret = h6_resolve_irq();
	if (ret)
		goto err_unmap;
	ret = irq_set_irq_type(requested_irq, IRQ_TYPE_LEVEL_HIGH);
	if (ret)
		pr_warn("snitch_job: irq_set_irq_type returned %d\n", ret);
	ret = request_irq(requested_irq, h6_irq_handler, IRQF_TRIGGER_HIGH,
			  "snitch_job", &h6_miscdev);
	if (ret)
		goto err_irq_mapping;
	ret = misc_register(&h6_miscdev);
	if (ret)
		goto err_free_irq;
	pr_info("snitch_job: ready at /dev/snitch_job, irq=%d mmio=0x%lx resident=%d\n",
		requested_irq, mmio_base, resident_mode);
	return 0;

err_free_irq:
	free_irq(requested_irq, &h6_miscdev);
err_irq_mapping:
	if (requested_irq_is_mapping)
		irq_dispose_mapping(requested_irq);
err_unmap:
	iounmap(regs);
	regs = NULL;
	return ret;
}

static void __exit h6_exit(void)
{
	misc_deregister(&h6_miscdev);
	h6_write(H6_REG_CONTROL, 0);
	h6_write(H6_REG_IRQ_ENABLE, 0);
	h6_write(H6_REG_IRQ_PENDING, H6_IRQ_PENDING);
	free_irq(requested_irq, &h6_miscdev);
	if (requested_irq_is_mapping)
		irq_dispose_mapping(requested_irq);
	iounmap(regs);
	pr_info("snitch_job: unloaded\n");
}

module_init(h6_init);
module_exit(h6_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("hero-tools educational bring-up");
MODULE_DESCRIPTION("DE1-SoC upstream Snitch blocking job driver");
