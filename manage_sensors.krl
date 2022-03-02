ruleset manage_sensors {
  meta {
    name "Manage Sensors"
    description <<
      Manages a collection of temperature sensors
    >>
    author "Tyla Evans"
    provides sensors, temperatures
    shares sensors, temperatures
    use module io.picolabs.wrangler alias wrangler
  }

  global {
    default_notification_number = "+13033324277"
    default_threshold = 78

    sensors = function() {
      ent:sensors
    }

    temperatures = function() {
      ent:sensors.map(
        function(v,k){
          name = k.klog("name:")
          eci = v{"eci"}.klog("eci:")
          ready = v{"ready"}.klog("ready")
          eci && ready => wrangler:picoQuery(eci,"temperature_store","temperatures",{}) | []
        })
    }
  }

  rule intialization {
    select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid
    always {
      ent:sensors := {}
    }
  }

  rule create_sensor {
    select when sensor new_sensor
    pre {
      name = event:attrs{"name"}.klog("name:")
      exists = (ent:sensors && ent:sensors >< name).klog("already exists:")
      ready = exists && ent:sensors{name}{"ready"}.klog("ready:")
    }
    if exists then
      send_directive(ready => "sensor_ready" | "initializing_sensor", {"sensor_name":name})
    notfired {
      ent:sensors{name} := {"ready": false}
      raise wrangler event "new_child_request"
        attributes { "name": name,
                     "backgroundColor": "#13A169" }
    }
  }

  rule store_sensor {
    select when wrangler new_child_created
    pre {
      eci = event:attrs{"eci"}.klog("eci:")
      name = event:attrs{"name"}.klog("name:")
    }
    if name then noop()
    fired {
      ent:sensors{name} := {"eci": eci, "ready": false}
    }
  }

  rule initiate_subscription_to_sensor {
    select when sensor_installer installation_finished
      wellKnown_eci re#(.+)#
      setting(wellKnown_eci)
    always {
      raise sensor event "subscription_request" attributes {
        "wellKnown_eci": wellKnown_eci
      }
    }
  }

  rule subscribe_to_sensor {
    select when sensor subscription_request
      wellKnown_eci re#(.+)#
      setting(wellKnown_eci)
    always {
      raise wrangler event "subscription" attributes {
        "wellKnown_Tx": wellKnown_eci,
        "Rx_role":"manager",
        "Tx_role":"sensor",
      }
    }
  }

  rule trigger_sensor_installation {
    select when wrangler new_child_created
    pre {
      eci = event:attrs{"eci"}.klog("eci:")
      auth_token = meta:rulesetConfig{"auth_token"}
      session_id = meta:rulesetConfig{"session_id"}
    }
    if eci then
      event:send(
        { "eci": eci,
          "eid": "install-ruleset",
          "domain": "wrangler",
          "type": "install_ruleset_request",
          "attrs": {
            "absoluteURL": meta:rulesetURI,
            "rid": "sensor_installer",
            "config": {
              "auth_token": auth_token,
              "session_id": session_id
            },
          }
        }
      )
  }

  rule initialize_sensor_profile {
    select when sensor_installer installation_finished
    pre {
      eci = event:attrs{"child_eci"}.klog("eci:")
      sensor = (ent:sensors.filter(function(v,k){v{"eci"} == eci})).klog("sensor:")
      name = (sensor.keys()[0]).klog("name:")
    }
    if name then
      event:send({
        "eci": eci,
        "domain": "sensor",
        "type": "profile_updated",
        "attrs": {
          "name": name,
          "temperature_threshold": default_threshold,
          "notification_number": default_notification_number
        }
      })
  }

  rule mark_sensor_ready {
    select when sensor_installer installation_finished
    pre {
      eci = event:attrs{"child_eci"}.klog("eci:")
      sensor = (ent:sensors.filter(function(v,k){v{"eci"} == eci})).klog("sensor:")
      name = (sensor.keys()[0]).klog("name:")
      sensor_eci = event:attrs{"sensor_eci"}.klog("sensor eci:")
    }
    if name then noop()
    fired {
      ent:sensors{name} := {"eci": eci, "sensor_eci": sensor_eci, "ready": true}
    }
  }

  rule delete_sensor {
    select when sensor unneeded_sensor
    pre {
      name = event:attrs{"name"}.klog("name:")
      exists = (ent:sensors >< name).klog("exists:")
      eci = ent:sensors{name}{"eci"}.klog("eci:")
    }
    if exists && eci then
      send_directive("deleting_sensor", {"sensor_name":name})
    fired {
      raise wrangler event "child_deletion_request"
        attributes {"eci": eci};
      clear ent:sensors{name}
    }
  }
}
