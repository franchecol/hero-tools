# Manual Quartus GUI Tutorial

This tutorial recreates the D0 LED/switch smoke test using only the Quartus GUI.
No build script is required.

The goal is:

```text
SW[9:0] -> LEDR[9:0]
```

That means every physical slide switch controls the matching red LED.

## 0. Open Quartus

Use the fixed launcher, or run:

```bash
/home/ftv/bin/quartus-gui
```

The GUI is forced through XWayland because Quartus 25.1 crashes in this Wayland
session otherwise.

## 1. Create A New Project

In Quartus:

```text
File -> New Project Wizard
```

Use these values:

```text
Working directory:
  /home/ftv/builds/hero-tools/fpga/de1-soc/d0_led_switches_gui_manual

Project name:
  de1_d0_led_switches

Top-level design entity:
  de1_d0_led_switches
```

When asked to add files, skip it for now.

When asked for device settings:

```text
Family:
  Cyclone V

Device:
  5CSEMA5F31C6
```

Finish the wizard.

## 2. Create The Verilog File

In Quartus:

```text
File -> New -> Design Files -> Verilog HDL File
```

Paste this:

```verilog
module de1_d0_led_switches (
    input  wire [9:0] SW,
    output wire [9:0] LEDR
);

    assign LEDR = SW;

endmodule
```

Save it as:

```text
de1_d0_led_switches.v
```

Add it to the project if Quartus asks.

If it does not ask:

```text
Project -> Add/Remove Files in Project
```

Then add:

```text
de1_d0_led_switches.v
```

## 3. Set The Top-Level Entity

In the Project Navigator, right-click:

```text
de1_d0_led_switches
```

Then select:

```text
Set as Top-Level Entity
```

## 4. Set Unused Pins Safely

This avoids driving random unused board pins.

Open:

```text
Assignments -> Device -> Device and Pin Options -> Unused Pins
```

Set:

```text
Reserve all unused pins:
  As input tri-stated
```

Click:

```text
OK -> OK
```

## 5. Assign DE1-SoC Pins

Open:

```text
Assignments -> Pin Planner
```

Add these pin assignments.

```text
┌───────────┬──────────┬──────────────┐
│ Node Name │ Location │ I/O Standard │
├───────────┼──────────┼──────────────┤
│ SW[0]     │ PIN_AB12 │ 3.3-V LVTTL  │
│ SW[1]     │ PIN_AC12 │ 3.3-V LVTTL  │
│ SW[2]     │ PIN_AF9  │ 3.3-V LVTTL  │
│ SW[3]     │ PIN_AF10 │ 3.3-V LVTTL  │
│ SW[4]     │ PIN_AD11 │ 3.3-V LVTTL  │
│ SW[5]     │ PIN_AD12 │ 3.3-V LVTTL  │
│ SW[6]     │ PIN_AE11 │ 3.3-V LVTTL  │
│ SW[7]     │ PIN_AC9  │ 3.3-V LVTTL  │
│ SW[8]     │ PIN_AD10 │ 3.3-V LVTTL  │
│ SW[9]     │ PIN_AE12 │ 3.3-V LVTTL  │
│ LEDR[0]   │ PIN_V16  │ 3.3-V LVTTL  │
│ LEDR[1]   │ PIN_W16  │ 3.3-V LVTTL  │
│ LEDR[2]   │ PIN_V17  │ 3.3-V LVTTL  │
│ LEDR[3]   │ PIN_V18  │ 3.3-V LVTTL  │
│ LEDR[4]   │ PIN_W17  │ 3.3-V LVTTL  │
│ LEDR[5]   │ PIN_W19  │ 3.3-V LVTTL  │
│ LEDR[6]   │ PIN_Y19  │ 3.3-V LVTTL  │
│ LEDR[7]   │ PIN_W20  │ 3.3-V LVTTL  │
│ LEDR[8]   │ PIN_W21  │ 3.3-V LVTTL  │
│ LEDR[9]   │ PIN_Y21  │ 3.3-V LVTTL  │
└───────────┴──────────┴──────────────┘
```

Close the Pin Planner after saving.

These pin names come from the Quartus 25.1 bundled `DE1_SoC_Board` platform.

## 6. Compile The Design

Run:

```text
Processing -> Start Compilation
```

Expected result:

```text
Full Compilation was successful
0 errors
```

Warnings about no clocks or no timing constraints are acceptable for this D0
test because the design is only combinational wires from switches to LEDs.

After compile, Quartus creates:

```text
de1_d0_led_switches.sof
```

## 7. Program The FPGA

Connect the DE1-SoC USB-Blaster cable.

Open:

```text
Tools -> Programmer
```

Set:

```text
Mode:
  JTAG
```

Click:

```text
Hardware Setup
```

Select:

```text
DE-SoC
```

Then close Hardware Setup.

First detect the real JTAG chain:

```text
Auto Detect
```

You should see two devices:

```text
1. SOCVHPS
2. 5CSEMA5
```

Important: the FPGA is the second JTAG device. The first device, `SOCVHPS`, is
the ARM/HPS side and should not receive the `.sof` file.

If Quartus asks whether to replace `5CSEMA5F31` with `5CSEMA5`, click:

```text
No
```

That warning usually means the `.sof` file was added before the real JTAG chain
was auto-detected. Start this programmer step again:

```text
Delete existing rows -> Auto Detect -> add/change file on the FPGA row
```

Attach the `.sof` file to the FPGA row:

```text
5CSEMA5
```

Use:

```text
Change File...
```

or:

```text
Add File...
```

and select:

```text
output_files/de1_d0_led_switches.sof
```

Enable the checkbox:

```text
Program/Configure
```

Click:

```text
Start
```

Expected result:

```text
Progress: 100%
Configuration succeeded
```

## 8. Test The Board

Move the physical switches:

```text
SW0 -> LEDR0
SW1 -> LEDR1
...
SW9 -> LEDR9
```

If a switch changes the matching LED, the D0 FPGA path works.

## 9. What This Proves

This confirms:

```text
PC Linux tools work
Quartus can compile for Cyclone V
USB-Blaster/JTAG works
The DE1-SoC FPGA fabric can be programmed
The physical switch and LED pins are correct
```

This still does not use:

```text
ARM Linux
microSD
HPS-to-FPGA bridge
Snitch
Occamy
```

Those come later.
