-- thinx.lua
-- THiNX Example device application

-- TODO: THX-69: Pure registration request.

-- Roadmap:
-- TODO: Perform update request and flash firmware over-the-air
-- TODO: Support MQTT
-- TODO: HTTPS proxy support
-- TODO: MDNS Resolver
-- TODO: convert to thinx module

dofile("config.lua")

mqtt_client = null

-- Prerequisite: WiFi connection
function connect(ssid, password)
    wifi.setmode(wifi.STATION)
    wifi.sta.config(ssid, password)
    wifi.sta.connect()
    tmr.alarm(1, 1000, 1, function()
        if wifi.sta.getip() == nil then
            print("Connecting " .. ssid .. "...")
        else
            tmr.stop(1)
            print("Connected to " .. ssid .. ", IP is "..wifi.sta.getip())
            thinx_register()
            do_mqtt()
        end
    end)
end

function thinx_register()
  url = 'http://thinx.cloud:7442/device/register' --  register/check-in device
  headers = 'Authentication' .. THINX_API_KEY .. '\r\n' ..
            'Accept: application/json\r\n' ..
            'Origin: device\r\n' ..
            'Content-Type: application/json\r\n' ..
            'User-Agent: THiNX-Client\r\n'
  data = '{"registration": {"mac": "'..thinx_device_mac()..'", "firmware": "'..THINX_FIRMWARE_VERSION..'", "version": "'..THINX_FIRMWARE_VERSION_SHORT..'", "hash": "' .. THINX_COMMIT_ID .. '", "alias": "' .. THINX_DEVICE_ALIAS .. '", "udid" :"' ..THINX_UDID..'" }}'
  http.post(url, headers, data,
    function(code, data)
      if (code < 0) then
        print("HTTP request failed")
      else
        print(code, data)
        if code == 200 then
          process_thinx_response(data)
      end
    end
  end)
end

function thinx_update()
  url = 'http://thinx.cloud:7442/device/firmware' --  register/check-in device
  headers = 'Authentication' .. THINX_API_KEY .. '\r\n' ..
            'Accept: */*\r\n' ..
            'Origin: device\r\n' ..
            'Content-Type: application/json\r\n' ..
            'User-Agent: THiNX-Client\r\n'

  -- API expects: mac, hash (?), checksum, commit, owner
  body = '{"registration": {"mac": "'..thinx_device_mac()..'", "firmware": "'..THINX_FIRMWARE_VERSION..'", "version": "'..THINX_FIRMWARE_VERSION_SHORT..'", "hash": "' .. THINX_COMMIT_ID .. '", "alias": "' .. THINX_DEVICE_ALIAS .. '", "udid" :"' ..THINX_UDID..'" }}'

  http.post(url, headers, body,
    function(code, data)
      if (code < 0) then
        print("HTTP request failed")
      else
        print(code, data)
        if code == 200 then
          -- TODO: install OTA udate
          process_thinx_response(data)
      end
    end
  end)
end

-- TODO: process incoming JSON response (both MQTT/HTTP) for register/force-update/update and forward others to client app)
function process_thinx_response(response_json)
    local response = ujson.loads(response_json)
    print("THiNX: response:")
    print(response)

    -- if response['registration'] as given by protocol
    local reg = response['registration']
    if reg then
      -- TODO: update device_info (global object in future, now just THINX_DEVICE_ALIAS, THINX_DEVICE_OWNER, THINX_API_KEY and THINX_UDID)
      THINX_DEVICE_ALIAS = reg['alias']
      THINX_DEVICE_OWNER = reg['owner']
      THINX_API_KEY = reg['apikey']
      THINX_UDID = reg['device_id']
      save_device_info()
    end

    -- if response['registration'] as given by protocol
    local upd = response['update']
    if upd then
      print("TODO: Fetch data, write to temp file and swap with init.lua")
    end
end

-- provides only current status as JSON so it can be loaded/saved independently
function get_device_info()
  -- TODO: save arbitrary data if secure
  device_info = {}
  device_info['alias'] = THINX_DEVICE_ALIAS
  device_info['owner'] = THINX_DEVICE_OWNER
  device_info['apikey'] = THINX_API_KEY
  device_info['device_id'] = THINX_UDID
  device_info['udid'] = THINX_UDID
  return device_info
end

-- apply given device info to current runtime environment
function apply_device_info(info)
    -- TODO: import arbitrary data if secure
    THINX_DEVICE_ALIAS = info['alias']
    THINX_DEVICE_OWNER = info['owner']
    THINX_API_KEY=info['apikey']
    THINX_UDID=info['device_id']
end

-- Used by response parser
function save_device_info()
  if file.open("thinx.cfg", "w") then
    info = ujson.dumps(get_device_info())
    file.write(info .. '\n')
    file.close()
  else
    print("THINX: failed to open config file for writing")
  end
end

-- Restores incoming data from filesystem overriding build-time-constants
function restore_device_info()
  if file.open("thinx.cfg", "r") then
    data = file.read('\n')
    file.close()
    info = ujson.loads(data)
    apply_device_info(info)
  else
    print("No config file found")
  end
end

function do_mqtt()
    mqtt_client = mqtt.Client(node.chipid(), 120, "username", "password") -- should be udid/apikey
    mqtt_client:lwt("/lwt", "{ \"connected\":false }", 0, 0)

    mqtt_client:on("connect", function(client)
        print ("connected")
    end)

    mqtt_client:on("offline", function(client)
        print ("offline")
        m:close();
    end)

    m:on("message", function(client, topic, data)
        print(topic .. ":" )
        process_mqtt(data)
        if data ~= nil then print("message: " .. data) end
    end)

    print("Connecting to MQTT to " .. target .. "...")
    mqtt_client:connect(THINX_MQTT_URL, THINX_MQTT_PORT, 0,
    function(client)
        print(":mconnected")
        m:subscribe("/device/"..THINX_UDID,0, function(client) print("subscribe success") end)
        m:publish("/device/"..THINX_UDID,"HELO",0,0)
    end,
    function(client, reason)
        print("failed reason: "..reason)
    end
)
end

function process_mqtt(response)
  print(response)
  process_thinx_response(response)
end

-- local platform helpers

function thinx_mac()
  return "VENDOR"..node.chipid()
end

-- main library function

function thinx()
    restore_device_info()
    connect(wifi_ssid, wifi_password) -- calls register an mqtt
end

-- saple app

thinx()
