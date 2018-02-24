ruleset sensor_profile {
    meta {
        shares get_profile
        provides get_profile
    }
    
    global {
        get_profile = function() {
            {
                "name": ent:name,
                "location": ent:location,
                "high": ent:high,
                "number": ent:number
            }
        }

        default_name = "sensor1";
        default_location = "bedroom";
        default_high = 80.0;
        default_number = "+14355121155";
    }

    rule intialization {
        select when wrangler ruleset_added where rids >< meta:rid
        always {
            ent:name := default_name;
            ent:location := default_location;
            ent:high := default_high;
            ent:number := default_number;
        }
    }
    rule update_sensor_profile {
        select when sensor profile_updated
        pre {
            sensor_name = event:attr("name").defaultsTo(ent:name)
            sensor_location = event:attr("location").defaultsTo(ent:location)
            sensor_high = event:attr("high").defaultsTo(ent:high)
            sensor_phone_number = event:attr("number").defaultsTo(ent:number)
        }
        
        always {
            ent:name := sensor_name;
            ent:location := sensor_location;
            ent:high := sensor_high;
            ent:number := sensor_phone_number;
        }
    }
}