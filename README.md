# AXIS DATA WIDTH CONVERTER
### Convert any data width to any other data width.
---

![image](docs/manual/img/AFRL.png)

---

  author: Jay Convertino   
  
  date: 2026.03.25  
  
  details: Simple data width converter for axis devices. Data widths must divide evenly.  
  
  license: MIT   
   
  Actions:  

  [![Lint Status](../../actions/workflows/lint.yml/badge.svg)](../../actions)  
  [![Manual Status](../../actions/workflows/manual.yml/badge.svg)](../../actions)  
  
---

### Version
#### Current
  - V2.0.0 - initial release of all size converter with flush last bytes.

#### Previous
  - V1.0.1 - bugs
  - V1.0.0 - initial release

### DOCUMENTATION
  For detailed usage information, please navigate to one of the following sources. They are the same, just in a different format.

  - [axis_data_width_converter.pdf](docs/manual/axis_data_width_converter.pdf)
  - [github page](https://johnathan-convertino-afrl.github.io/axis_data_width_converter/)

### PARAMETERS

 *   SLAVE_WIDTH    - Width of the slave input bus in bytes
 *   MASTER_WIDTH   - Width of the master output bus in bytes
 *   FLUSH_LAST     - Once last bytes are received, force them out regardless of size (no longer ready to accept more data once this happens).

### COMPONENTS
#### SRC

* axis_data_width_converter.v
  
#### TB

* tb_axis.v
* tb_cocotb
  
### FUSESOC

* fusesoc_info.core created.
* Simulation uses icarus to run data through the core. Verification added, will auto end sim when done.

#### Targets

* RUN WITH: (fusesoc run --target=sim VENDER:CORE:NAME:VERSION)
  - default (for IP integration builds)
  - lint
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
