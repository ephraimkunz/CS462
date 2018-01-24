ruleset twilio_v2_api {
    meta {
        configure using account_sid = ""
                        auth_token = ""
        provides 
            send_sms,
            messages
    }

    global {
        send_sms = defaction(to, from, message) {
            base_url = <<https://#{account_sid}:#{auth_token}@api.twilio.com/2010-04-01/Accounts/#{account_sid}/>>
            http:post(base_url + "Messages.json", form = {
                "From":from,
                "To":to,
                "Body":message
            })
        }

        messages = function(to, from, pageSize) {
            base_url = <<https://#{account_sid}:#{auth_token}@api.twilio.com/2010-04-01/Accounts/#{account_sid}/>>;
            queryString = {};

            queryString = (pageSize.isnull() || pageSize == "") => queryString | queryString.put({"PageSize":pageSize});
            queryString = (to.isnull() || to == "") => queryString | queryString.put({"To":to});
            queryString = (from.isnull() || from == "") => queryString | queryString.put({"From":from});
            queryString.klog("Testing: ");
            
            response = http:get(base_url + "Messages.json", qs = queryString);
            response{"content"}.decode(){"messages"}
        }
    }
}