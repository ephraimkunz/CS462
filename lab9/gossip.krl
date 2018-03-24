ruleset gossip_ruleset {

    rule gossip_heartbeat {
        select when gossip heartbeat
    }

    rule gossip_rumor {
        select when gossip rumor
    }

    rule gossip_seen {
        select when gossip seen
    }

    rule gossip_process {
        select when gossip process
    }
}

