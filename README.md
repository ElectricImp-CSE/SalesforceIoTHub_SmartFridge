# Smart Fridge Salesforce IoTHub

Modified Smart Fridge code for Imp Explorer Kit. 

Application takes temperature, humidity and light readings (used to determine if door is open or closed) in a loop. To conserve power device is put to sleep between readings and a timer is set to schedule when the device should connect to the imp server and send stored readings/door status to the agent. The application also uses the accelerometer interrupt in conjunction with the light sensor to determine if the fridge door has changed state. If there is a change in the door status the device will connect immediately and send all stored readings and the new door status to the agent.  

The logic for the alerts listed below have been removed from the squirrel code, so they can be implemented by IoTHub Cloud: 
* Temperature above threshold for too long (excluding time when door has been is open)
* Humidity above threshold for too long (excluding time when door has been is open)
* Door open for too long
