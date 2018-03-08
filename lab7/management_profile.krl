ruleset management_profile {
    meta {
        use module com.ephraimkunz.api_keys
        use module twilio_v2_api alias twilio
            with account_sid = keys:twilio("account_sid")
            auth_token =  keys:twilio("auth_token")
    }
    
    global {
        default_number = "+14355121155";
        from_number = "+14352653308"
    }

    rule send_text {
        select when management_profile send_message
        pre {
            message = event:attr("message")
            toNumber = ent:number
        }

        twilio:send_sms(toNumber,
                            from_number,
                            message)
    }

    rule initialization {
        select when wrangler ruleset_added where rids >< meta:rid
        always {
            ent:number := default_number;
        }
    }
    rule update_sensor_profile {
        select when sensor profile_updated
        pre {
            sensor_phone_number = event:attr("number").defaultsTo(ent:number)
        }
        
        always {
            ent:number := sensor_phone_number;
        }
    }
}