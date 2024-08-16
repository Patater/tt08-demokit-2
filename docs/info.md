<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This design outputs a 6-bit rainbow tunnel demo on VGA.

### Screenshots

![Tunnel](Tunnel.png)
<br />
Default

### Video

An online version of a different (software rather than hardware)
implementation, of the rainbow tunnel can be found at
<https://www.patater.com/demokit/tunnel/>.

## How to test

If wanting to test without hardware, use [the VGA
playground](https://tinytapeout.github.io/vga-playground/). Copy and paste the
contents of the entire `src/project.v` file into the playground's text editor,
replacing all previous content. Then, change the name of the module from
`tt_um_patater_demokit_2` to `tt_um_vga_example` and the simulator will start
running in your browser.

If testing with hardware, use a [TinyVGA
PMOD](https://github.com/mole99/tiny-vga). Clock the design with 25.175 MHz as
described in `info.yaml` (25.157 MHz is standard for 60 Hz 640x480 VGA video).

If testing with lower level simulation tools, an incomplete cocotb test bench
(`test/test.py`) is provided. Passing the tests in the cocotb bench is no
guarantee that the design will work.

## External hardware

External hardware required:
 - [TinyVGA PMOD](https://github.com/mole99/tiny-vga)
