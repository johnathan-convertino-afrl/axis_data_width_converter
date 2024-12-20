# AXIS DATA WIDTH CONVERTER
### Simple data width converted for ratios that divide into one another.

![image](docs/manual/img/AFRL.png)

---

   author: Jay Convertino   
   
   date: 2023.02.01  
   
   details: Simple data width converter for axis devices. Data widths must divide evenly.  
   
   license: MIT   
   
---

### Version
#### Current
  - V1.0.0 - initial release

#### Previous
  - none

### DOCUMENTATION
  For detailed usage information, please navigate to one of the following sources. They are the same, just in a different format.

  - [axis_data_width_converter.pdf](docs/manual/axis_data_width_converter.pdf)
  - [github page](https://johnathan-convertino-afrl.github.io/axis_data_width_converter/)

### DEPENDENCIES
#### Build

  - AFRL:utility:helper:1.0.0

#### Simulation

  - AFRL:simulation:axis_stimulator
  - AFRL:simulation:clock_stimulator
  - AFRL:utility:sim_helper

### PARAMETERS

* SLAVE_WIDTH  : DEFAULT = 1 : Slave width in bytes.
* MASTER_WIDTH : DEFAULT = 1 : Master width in bytes.
* REVERSE : DEFAULT = 0 : Set to 1 to reverse the order of how bytes are output.

### COMPONENTS
#### SRC

* axis_data_width_converter.v
  
#### TB

* tb_axis.v
  
### FUSESOC

* fusesoc_info.core created.
* Simulation uses icarus to run data through the core. Verification added, will auto end sim when done.

#### Targets

* RUN WITH: (fusesoc run --target=sim VENDER:CORE:NAME:VERSION)
  - default (for IP integration builds)
  - sim
  - sim_reduce
  - sim_rand_data_reduce
  - sim_rand_ready_rand_data_reduce
  - sim_8bit_count_data_reduce
  - sim_rand_ready_8bit_count_data_reduce
  - sim_increase
  - sim_rand_data_increase
  - sim_rand_ready_rand_data_increase
  - sim_8bit_count_data_increase
  - sim_rand_ready_8bit_count_data_increase
  - sim_cocotb
