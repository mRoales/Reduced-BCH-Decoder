import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, ClockCycles

def generar_ui_in(sel_mux_0, sel_mux_1, n_inv, enable):
    """Función auxiliar para empaquetar las señales en el bus ui_in[7:0]"""
    # ui_in[1:0] = sel_mux_0
    # ui_in[3:2] = sel_mux_1
    # ui_in[6:4] = n_inv
    # ui_in[7]   = enable
    val = (sel_mux_0 & 0x03)
    val |= ((sel_mux_1 & 0x03) << 2)
    val |= ((n_inv & 0x07) << 4)
    val |= ((enable & 0x01) << 7)
    return val

def generar_uio_in(tx_ready, op_mode):
    """Función auxiliar para empaquetar los controles en el bus uio_in[7:0]"""
    # uio_in[0] = tx_ready
    # uio_in[1] = op_mode
    # Los bits [7:2] se dejan en 0 ya que se ignoran o se configuran como salidas
    val = (tx_ready & 0x01)
    val |= ((op_mode & 0x01) << 1)
    return val

@cocotb.test()
async def test_project(dut):
    dut._log.info("***********_____STARTING COCOTB TOP LEVEL SIMULATION_____***********")
    
    # ------------------------------------------------------------------------
    # 1. Configuración del Reloj y Señal Ena
    # ------------------------------------------------------------------------
    CLK_PRD = 20  # Período del reloj de 20ns
    clock = Clock(dut.clk, CLK_PRD, unit="ns")
    cocotb.start_soon(clock.start())
    
    dut.ena.value = 1  # Habilitamos el diseño dentro del entorno de Tiny Tapeout

    # ------------------------------------------------------------------------
    # 2. Inicialización del Estado de Pines (Primer bloque initial)
    # ------------------------------------------------------------------------
    dut.rst_n.value = 0
    dut.ui_in.value = generar_ui_in(sel_mux_0=0, sel_mux_1=0, n_inv=0, enable=0)
    dut.uio_in.value = generar_uio_in(tx_ready=0, op_mode=0)

    # Espera inicial: 4 ciclos completos + desfase de 0.8 del período
    await ClockCycles(dut.clk, 4)
    await Timer(int(0.8 * CLK_PRD), units="ns")
    dut.rst_n.value = 1

    # ------------------------------------------------------------------------
    # 3. Flujo Secuencial de Estímulos Mapeados (Segundo bloque initial)
    # ------------------------------------------------------------------------
    
    # --- Bloque de Prueba 1 ---
    await ClockCycles(dut.clk, 6)
    await Timer(int(0.8 * CLK_PRD), units="ns")
    dut.ui_in.value = generar_ui_in(sel_mux_0=0, sel_mux_1=1, n_inv=0, enable=0)

    await ClockCycles(dut.clk, 4)
    dut.ui_in.value = generar_ui_in(sel_mux_0=0, sel_mux_1=1, n_inv=0, enable=1)
    
    await ClockCycles(dut.clk, 4)
    dut.uio_in.value = generar_uio_in(tx_ready=1, op_mode=0)
    
    await ClockCycles(dut.clk, 200)
    
    # --- Bloque de Prueba 2 (Reset y Cambio de Desafío) ---
    dut.rst_n.value = 0
    dut.ui_in.value = generar_ui_in(sel_mux_0=0, sel_mux_1=1, n_inv=0, enable=0)
    
    await ClockCycles(dut.clk, 4)
    dut.rst_n.value = 1
    dut.ui_in.value = generar_ui_in(sel_mux_0=0, sel_mux_1=2, n_inv=4, enable=0)
    
    await ClockCycles(dut.clk, 4)
    dut.ui_in.value = generar_ui_in(sel_mux_0=0, sel_mux_1=2, n_inv=4, enable=1)
    
    await ClockCycles(dut.clk, 200)
    
    # --- Bloque de Prueba 3 ---
    dut.rst_n.value = 0
    dut.ui_in.value = generar_ui_in(sel_mux_0=0, sel_mux_1=2, n_inv=4, enable=0)
    
    await ClockCycles(dut.clk, 4)
    dut.rst_n.value = 1
    dut.ui_in.value = generar_ui_in(sel_mux_0=3, sel_mux_1=2, n_inv=0, enable=0)
    
    await ClockCycles(dut.clk, 4)
    dut.ui_in.value = generar_ui_in(sel_mux_0=3, sel_mux_1=2, n_inv=0, enable=1)
    
    await ClockCycles(dut.clk, 200)
    
    # --- Bloque de Prueba 4 (Inyección de op_mode a través de uio_in) ---
    dut.rst_n.value = 0
    dut.ui_in.value = generar_ui_in(sel_mux_0=3, sel_mux_1=2, n_inv=0, enable=0)
    
    await ClockCycles(dut.clk, 4)
    dut.rst_n.value = 1
    dut.ui_in.value = generar_ui_in(sel_mux_0=3, sel_mux_1=2, n_inv=0, enable=0)
    
    await ClockCycles(dut.clk, 4)
    dut.ui_in.value = generar_ui_in(sel_mux_0=3, sel_mux_1=2, n_inv=0, enable=1)
    
    await ClockCycles(dut.clk, 20)
    dut.uio_in.value = generar_uio_in(tx_ready=1, op_mode=1)  # Activamos op_mode
    
    await ClockCycles(dut.clk, 20)
    
    dut._log.info("***********_____SIMULATION COMPLETED_____***********")
