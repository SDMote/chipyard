package chipyard.config

import chisel3._
import chipyard._
import chipyard.iocell._
import chisel3.util._
import org.chipsalliance.cde.config.{Config}
import chipyard.iobinders.{IOCellKey}
import chisel3.experimental.{Analog, attach}


// BlackBoxes corresponding to the IHP IO cells, with their Bundle definitions
class sg13g2_IOPadIn extends BlackBox with HasBlackBoxResource {
    val io = IO(new Bundle {
        val pad   = Input(Bool())
        val p2c   = Output(Bool())
    }) 
    addResource("/vsrc/sg13g2_io.v")
}
class sg13g2_IOPadOut30mA extends BlackBox with HasBlackBoxResource {
    val io = IO(new Bundle {
        val pad   = Output(Bool())
        val c2p   = Input(Bool())
    })
    addResource("/vsrc/sg13g2_io.v")
}
class sg13g2_IOPadAnalog extends BlackBox with HasBlackBoxResource {
    val io = IO(new Bundle {
        val pad   = Analog(1.W)
        val padres= Analog(1.W)
    })
    addResource("/vsrc/sg13g2_io.v")
}

// Implementation of the connection between port Bundle and pad Bundle
class IHPDigitalInIOCell extends RawModule with DigitalInIOCell {
    val io = IO(new DigitalInIOCellBundle)
    val pad = Module(new sg13g2_IOPadIn)
    pad.io.pad := io.pad
    io.i := pad.io.p2c 
}

class IHPDigitalOutIOCell extends RawModule with DigitalOutIOCell {
    val io = IO(new DigitalOutIOCellBundle)
    val pad = Module(new sg13g2_IOPadOut30mA)
    pad.io.c2p := io.o
    io.pad := pad.io.pad
}

class IHPAnalogIOCell extends RawModule with AnalogIOCell {
    val io = IO(new AnalogIOCellBundle)
    val pad = Module(new sg13g2_IOPadAnalog)
    attach(io.pad, pad.io.pad)
    attach(io.pad, pad.io.padres)
}

// IO cell types configuration
case class IHPIOCellParams() extends IOCellTypeParams {
    def analog()    = Module(new GenericAnalogIOCell)
    def gpio()      = Module(new GenericDigitalGPIOCell)
    def input()     = Module(new IHPDigitalInIOCell)
    def output()    = Module(new IHPDigitalOutIOCell)
}

class WithIHPIOCells extends Config((site, here, up) => {
    case IOCellKey => IHPIOCellParams()
})