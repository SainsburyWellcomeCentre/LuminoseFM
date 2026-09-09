# LuminoseFM
This project  is to build BPOD protocol and other helper/utility files to perform freely-moving 2-AFC for the luminose project.

## Behaviour box
The behaviour box is a red acrylic box with the dimensions 18 cm x 18 cm x 23 cm (w x l x h). Three behaviouir ports are placed at a height of 1.2 cm, with a distance of 6 cm between the centre of each port. It's placed on a base plate and a cover designed to allow wires to pass through, but making it difficult for the mouse to climb out.

## For sleep 
A red acrylic cover designed to slot onto the homecage. This allows to record pre- or post-behaviour sleep without disconnecting tethered optical patch cords and/ or neuropixel cables. 

## Hardware
This project is for controlling the behaviour box using a [BPOD state machine r2+](https://sanworks.github.io/Bpod_Wiki/assembly/state-machine-assembly-2%2B/). It is connected to the computer using a USB cable. The connected components can be found by the method BpodSystem.StateMachineInfo or from the image that I have saved in the doc (./doc/BpodSystemInfo.png) The behaviour rig has the following components connected to the BPOD:

- Mouse Behaviour ports
These are controlled by [port interface boards](https://sanworks.github.io/Bpod_Wiki/assembly/port-breakout-board-assembly/). Each port interface board connects one infrared photo-gate, one LED and one solenoid valve with the Bpod state machine via an Ethernet cable. This version of BPOD has 5 behaviour ethernet ports, that are connected as follows -

    - Port 1 - Left 
    - Port 2 - Centre
    - Port 3 - Right 
    - Port 4 - Air valve (this is connected to an interface board and switched on/ off valve to control the flow of compressed air; the photo-gate and LED are inactive)
    - Port 5 - House light (connected to a LED driver that switches on/ off the white inside the rig; this is useful for pre- or post-behaviour sleep)

- Digital OUT 
The dedicated digital output ports will be used for controling and delivering the optogenetic stimuli. We will use transgenic mice expressing channelrhodopsin in olfactory sensory neurons (OSN-ChR). The optogenetic stimulus will be a spatiotemporal pattern of 100 um light spots delivered on the olfactory bulb of these mice, via a custom-made fiber bundle (see ./docs/fiber_bundle_design). We have two versions of this bundle 1. a 2-to-19 with ch1 and ch2 controlling 10 spots and 9 spots patterns, and 2. a 4-to-19 with ch1 and ch2 controlling any two of the 5 spots, 5 spots, 5 spots, and 4 spots patterns (Note that only two channels can be connected to the commutator, so the two patterns in the 4-to-19 version has to be physically plugged in when a change from the operation two channels, is desired). These channles are connected to a Doric blue LED with two LED channels, which can be driven separately using BNC cables. These are in turn connected to output1 and output2 of a pulsepal. The Input1 and Input2 of this pulsepal is driven by BNC1 and BNC2 of BPOD. So a optical pattern stimulus will be a spatiotemporal pattern of ON/OFF states of BNC1/BNC2 channels for the stimulus delivery period. 

    - BNC1 -> connected to pulsepal IN1 -> pulsepal OUT1 connected to LED1 -> optical pattern 1 
    - BNC2 -> connected to pulsepal IN2 -> pulsepal OUT2 connected to LED2 -> optical pattern 2

- Flex I/O 
Bpod Finite State Machine r2+ builds on r2.5 with additional onboard I/O: - 4 Flex I/O Channels can each be configured as: - Digital Output (5V TTL) - Digital Input (5V tolerant) - Analog Input (12-bit, 0-5V range, 1kHz sampling) - Analog Output (12-bit, 0-5V range).
    - Flex I/O 1 - Connected to the flow meter - configure as Analog Input
    - Flex I/O 2 - Sync TTL - configured as digital output 
    The sync TTL is a train of pseudo-random TTLs sent out to a BNC-splitter that is externally powered and is scalable. This is then channeled to other acquisition devices (e.g. Neuropixel OneBox or NI-1083, Camera 1, Camera 2, and so on).

- Modules 
module ports are specialized high-speed communication channels designed to connect external hardware extensions (modules) to the core state machine. 

    - [HiFi module](https://sanworks.github.io/Bpod_Wiki/assembly/hifi-module-assembly/) - this is connected to an amplifier card, which is connected to a custom-made speaker. The HiFi module is connected to BPOD using an ethernet cable and also connected directly to the computer via a USB cable. 

## Protocol
For user guide see - [https://sanworks.github.io/Bpod_Wiki/user-guide/]. The protocol will live as luminoseFM.m file in the root folder of this project (no nesting). Other helper/ utility files/ methods/ classes will be organized suitably in appropriate folders.

MATLAB directory - /mnt/c/Users/harrislab/Documents/MATLAB
Bpod_Gen2, Bpod Local, PulsePal directories are cloned into this directory and have been added to MATLAB path. The working directory is located in /mnt/c/Users/harrislab/Documents/MATLAB/HarrisLabBpodProtocols/LuminoseFM.

Protocol examples are located in /mnt/c/Users/harrislab/Documents/MATLAB/Bpod_Gen2/Examples/Protocols. 

### Task structure and GUI
The protocol and GUI should be designed so that it can be generalized for any 2-AFC with the schema 
Cue -> poke into centre port -> wait for stimulus -> hold nose poke till stimulus delivery is over -> reward in the desired port (left or right) -> restart trial

The behabiour rig has port light (LED), sound, air (centre port), optogenetic stimulus through BNC1 and BNC2. So, an ideal generalized workflow would give choices to arbitrarily choose from these (e.g. stimulus can be optogenetic pattern, sound, and so on)

Important note - since this task needs fast real-time control of the rig, memory usage must be optimized to avoid any unnecessary lags between state transition. This may include, but not limited to using the TrialManager object, optimizing static/ dynamic allocation of memory within the statemachine loop during a trial, saving data at optimal intervals, displaying a on-line plots that are essential, and so on.

Review the following and suggest better flow for the user or alternative workflows that make more sense -
A notebook (BPOD has a notebook feature)
The GUI could be set up such that separate tabs with 
- Experiment metadata (like any)
- training stage (habituation, training, experiment), contingency (e.g. stimulus A -> go left and vice versa), bias correction  
- Cue (with options to choose light, sound, air in combinations or alone, ability to set parameters independantly)
- Stimulus - total duration, frequency (e.g. 20 hz needed for ChR or constant on) - pattern 1 and pattern 2
    - LED/ sound/ opto pattern/ air
    - pulsepal params
    - If pattern, 
        - A vs B, 
        - mixture of A and B (spatiotemporal patterns with/ without overlap; with or without duration(A + B) <= duration(A) + duration(B))
        - Arbitrary sequences of A and B
        - anything else, maybe a graphic stimulus designer at the beginning of the session? 
- Reward 
    - water reward (by opening valves at left or right port)

### Online plots
- stimulus and choice plot (choices color coded as correct/ incorrect)
- learning curves - trial vs performance
- bar graph showing performance for left/ right trials and/ or plot showing 
- trial vs reaction time 
- opto vs control trials if relevant 
- psychometric, if relevant

### Controlling the Doric LED device from MATLAB (at a later stage - ignore for now)
The API to control the Doric LEDs is located in /mnt/c/Users/harrislab/Documents/MATLAB/DoricSystemDLL.

This will allow users to set LED power and other relveant parametres directly from MATLAB. To be decided - does it need a different package or should it be integrated into this protocol folder?