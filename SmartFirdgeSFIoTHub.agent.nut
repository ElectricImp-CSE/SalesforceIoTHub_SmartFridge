// MIT License
//
// Copyright 2017 Electric Imp
//
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
// EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
// OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
// ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.

// Utility Libraries
#require "bullwinkle.class.nut:2.3.2"

// Class that receives and handles data sent from device SmartFridgeApp
/***************************************************************************************
 * SmartFrigDataManager Class:
 *      Handle incoming device readings and events
 *      Set handler for streaming data
 *      Average temperature and humidity readings
 *
 * Dependencies
 *      Bullwinle (passed into the constructor)
 **************************************************************************************/
class SmartFrigDataManager {

    _debug = true;
    _streamReadingsHandler = null;

    // Class instances
    _bull = null;

    /***************************************************************************************
     * Constructor
     * Returns: null
     * Parameters:
     *      bullwinkle : instance - of Bullwinkle class
     **************************************************************************************/
    constructor(bullwinkle, debug = false) {
        _bull = bullwinkle;
        _debug = debug;
        openListeners();
    }

     /***************************************************************************************
     * openListeners
     * Returns: null
     * Parameters: none
     **************************************************************************************/
    function openListeners() {
        _bull.on("update", _readingsHandler.bindenv(this));
    }

    /***************************************************************************************
     * setStreamReadingsHandler
     * Returns: null
     * Parameters:
     *      cb : function - called when new reading received
     **************************************************************************************/
    function setStreamReadingsHandler(cb) {
        _streamReadingsHandler = cb;
    }

    // ------------------------- PRIVATE FUNCTIONS ------------------------------------------

    /***************************************************************************************
     * _getAverage
     * Returns: null
     * Parameters:
     *      readings : table of readings
     *      type : key from the readings table for the readings to average
     *      numReadings: number of readings in the table
     **************************************************************************************/
    function _getAverage(readings, type, numReadings) {
        if (numReadings == 1) {
            return readings[0][type];
        } else {
            local total = readings.reduce(function(prev, current) {
                    return (!(type in prev)) ? prev + current[type] : prev[type] + current[type];
                })
            return total / numReadings;
        }
    }

    /***************************************************************************************
     * _readingsHandler
     * Returns: null
     * Parameters:
     *      message : table - message received from bullwinkle listener
     *      reply: function that sends a reply to bullwinle message sender
     **************************************************************************************/
    function _readingsHandler(message, reply) {
        local data = message.data;
        local streamingData = { "ts" : time() };
        local numReadings = data.readings.len();

        // send ack to device (device erases this set of readings/events when ack received)
        reply("OK");

        if (_debug) {
            server.log("in readings handler")
            server.log(http.jsonencode(data.readings));
            server.log(http.jsonencode(data.doorStatus));
            server.log("Current time: " + time())
        }

        if ("readings" in data && numReadings > 0) {

            // Update streaming data table with temperature and humidity averages
            streamingData.temperature <- _getAverage(data.readings, "temperature", numReadings);
            streamingData.humidity <- _getAverage(data.readings, "humidity", numReadings);
        }

        if ("doorStatus" in data) {
            // Update streaming data table
            streamingData.door <- data.doorStatus.currentStatus;
        }

        // send streaming data to handler
        _streamReadingsHandler(streamingData);

    }

}

/***************************************************************************************
 * SalesforceIoTHub Class:
 *      Sends data to Salesforce
 **************************************************************************************/
class SalesforceIoTHub {

    _connectionURL = null;
    _token = null;
    _debug = null;

    constructor(connectionURL, token, debug) {
        _connectionURL = connectionURL;
        _token = token;
        _debug = debug;
    }

    function send(event, cb = null) {
        // Build the request
        local headers = { "Content-Type": "application/json",
                          "Authorization": "Bearer " + _token};

        local iotBody = http.jsonencode(event);
        if (_debug) server.log("Sending event to IoT Cloud. iotBody=" + iotBody);

        http.post(_connectionURL, headers, iotBody).sendasync(function(resp) {
            local err = null;
            if (resp.statuscode != 200) {
                err = "[Error] status code: " + resp.statuscode;
                if (_debug) server.log("Ensure INPUT_CONN_URL and BEARER_TOKEN are configured correctly.");
            }
            if (cb) imp.wakeup(0, function() {
                cb(err, resp);
            }.bindenv(this))
        }.bindenv(this))        
    }
}

/***************************************************************************************
 * Application Class:
 *      Sends events to Salesforce IotHub
 *
 * Dependencies
 *      Bullwinkle Library
 *      SmartFrigDataManager Class
 *      SalesforceIoTHub Class
 **************************************************************************************/
class Application {

    static DEBUG_LOGGING = true;

    _dm = null;
    _deviceID = null;
    _iotHub = null;


    /***************************************************************************************
     * Constructor
     * Returns: null
     * Parameters:
     *      connectionURL : string - IoT hub Input connection URL)
     *      token : string - IoT hub bearer token)
     **************************************************************************************/
    constructor(connectionURL, token) {
        _deviceID = imp.configparams.deviceid.tostring();
        
        initializeClasses(connectionURL, token);
        _dm.setStreamReadingsHandler(streamReadingsHandler.bindenv(this));
    }

    /***************************************************************************************
     * initializeClasses
     * Returns: null
     * Parameters:
     *      key : string - Yor Consumer Key (created in Salesforce App settings)
     *      secret : string - Yor Consumer Secret (created in Salesforce App settings)
     **************************************************************************************/
    function initializeClasses(connectionURL, token) {
        local _bull = Bullwinkle();

        _dm = SmartFrigDataManager(_bull, DEBUG_LOGGING);
        _iotHub = SalesforceIoTHub(connectionURL, token, DEBUG_LOGGING);
    }

    /***************************************************************************************
     * sendEvent
     * Returns: null
     * Parameters:
     *      data : table - temperature, humidity, door status and ts
     *      cb(optional) : function - callback executed when http request completes
     **************************************************************************************/
    function sendEvent(data, cb = null) {

        // Build table to send to IoTHub
        local event = { "device_id" : _deviceID };
        if ("temperature" in data) { 
            event.tempC <- data.temperature;
            event.tempF <- (data.temperature * 1.8) + 32;
        }
        if ("humidity" in data) event.humidity <- data.humidity;
        if ("door" in data) event.door <- data.door;

        // Send to IotHub
        _iotHub.send(event, cb);
    }

    /***************************************************************************************
     * streamReadingsHandler
     * Returns: null
     * Parameters:
     *      reading : table - temperature, humidity and door status
     **************************************************************************************/
    function streamReadingsHandler(reading) {
        if (DEBUG_LOGGING) server.log(http.jsonencode(reading));
        sendEvent(reading, iotHubResHandler);
    }

    /***************************************************************************************
     * iotHubResHandler
     * Returns: null
     * Parameters:
     *      err : string/null - error message
     *      respData : table - response table
     **************************************************************************************/
    function iotHubResHandler(err, respData) {
        if (err) {
            server.error(http.jsonencode(err));
        } else {
            server.log("Data successfully sent to IoT hub");
        }
    }

    /***************************************************************************************
     * formatTimestamp
     * Returns: time formatted as "2015-12-03T00:54:51Z"
     * Parameters:
     *      ts (optional) : integer - epoch timestamp
     **************************************************************************************/
    function formatTimestamp(ts = null) {
        local d = ts ? date(ts) : date();
        return format("%04d-%02d-%02dT%02d:%02d:%02dZ", d.year, d.month+1, d.day, d.hour, d.min, d.sec);
    }
}


// RUNTIME
// ---------------------------------------------------------------------------------

// IoT Cloud CONSTANTS
// ----------------------------------------------------------
// IoT Cloud settings - TODO: update with values from your configuration
const INPUT_CONN_URL = "UPDATE ME";
const BEARER_TOKEN = "UPDATE ME";

// Start Application
Application(INPUT_CONN_URL, BEARER_TOKEN);
