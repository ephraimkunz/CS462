ruleset manage_sensors {
    meta {
        shares __testing, sensors, getAllTemps
    }
    global {
        sensors = function() {
            ent:sensors
        }

        cloud_url = "http://localhost:8080/sky/cloud/";

        getTemp = function(v, k) {
            eci = v{"eci"};
            url = cloud_url + eci + "/temperature_store/temperatures";
            response = http:get(url);
            response{"content"}.decode();
        }

        getAllTemps = function() {
            sensors().map(getTemp)
        }

        defaultThreshold = 77.5;

        __testing = { "queries": [ { "name": "__testing" }, {"name": "sensors"}, {"name": "getAllTemps"} ],
                        "events": [ { "domain": "sensor", "type": "new_sensor",
                                    "attrs": [ "name" ] },
                                    {"domain": "collection", "type": "empty",
                                    "attrs": []},
                                    {"domain": "sensor", "type": "unneeded_sensor", 
                                    "attrs": ["name"]} ] }
    }

    rule empty_collection {
        select when collection empty
        always {
            ent:sensors := {}
        }
    }

    rule create_new_sensor {
        select when sensor new_sensor
        pre {
            name = event:attr("name")
            exists = ent:sensors >< name
        }

        if not exists then
            noop()
        fired {
            raise wrangler event "child_creation"
                attributes {"name": name, "color": "#e06238", "rids": ["temperature_store", "sensor_profile", "wovyn_base"]}
        }
    }

    rule store_new_sensor {
        select when wrangler new_child_created
        pre {
            the_sensor = {"id": event:attr("id"), "eci": event:attr("eci")}
            sensor_name = event:attr("name")
        }

        event:send(
            { "eci": the_sensor{"eci"}, "eid": "set_profile",
                "domain": "sensor", "type": "profile_updated",
                "attrs": { "name": sensor_name, "high": defaultThreshold } } )

        always {
            ent:sensors := ent:sensors.defaultsTo({});
            ent:sensors{[sensor_name]} := the_sensor
        }
    }

    rule remove_unneeded_sensor {
        select when sensor unneeded_sensor
        pre {
            name = event:attr("name")
            exists = ent:sensors >< name
            sensor = ent:sensors{name}.klog("Sensor to delete")
        }

        if exists then
            noop()
        fired {
            raise wrangler event "child_deletion"
                attributes sensor;
            ent:sensors := ent:sensors.delete([name])
        }
    }
}