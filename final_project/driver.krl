ruleset driver_ruleset {

    rule auto_accept {
        select when wrangler inbound_pending_subscription_added
        pre {
            attributes = event:attrs.klog("subcription:")
        }
        always {
            raise wrangler event "pending_subscription_approval"
            attributes attributes
        }
    }
}