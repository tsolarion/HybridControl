# Hybrid_Control

Configuration 12.03.2019:

The master branch is the version created by Michael Hersche before he left. This version was not tested on the hardware but it acts as a reference design. 


Tested non-compensated controller:

This contains the tested non compensated controller from Jan. 2019. 


Tested compensated controlller:

This contains the improved version that was also tested on teh hardware on Feb. 2019. This includes the extra feature with the set resistive load. 
The improved version is documented in overleaf in a separate file.
The controller is compensating the initial rise by having a constant corresponding to a 6us time delay. 
The Rset can be either set to the real value resulting to a more precise controller or to 0. In this case it will make the calculations based on the voltage measurements. 
