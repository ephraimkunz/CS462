ruleset sensor_profile {
    meta {
        
    }
    global {

    }
    rule update_sensor_profile {
        select when sensor profile_updated
        pre {
            sensor_name = attr:name
            sensor_location = attr:location
            sensor_high = attr:high
            sensor_phone_number = attr:number
        }

        always {
            ent:name := sensor_name;
            ent:high := sensor_high;
            ent:location := sensor_location;
            ent:number := sensor_phone_number;
        }
    }
}