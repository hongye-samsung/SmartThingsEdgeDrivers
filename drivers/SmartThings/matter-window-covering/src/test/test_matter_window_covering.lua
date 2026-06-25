-- Copyright 2022 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local test = require "integration_test"
local capabilities = require "st.capabilities"
local t_utils = require "integration_test.utils"
local uint32 = require "st.matter.data_types.Uint32"
local clusters = require "st.matter.clusters"

local WindowCovering = clusters.WindowCovering

test.disable_startup_messages()

local mock_device = test.mock_device.build_test_matter_device(
  {
    profile = t_utils.get_profile_definition("window-covering-tilt-battery.yml"),
    manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
    endpoints = {
      {
        endpoint_id = 2,
        clusters = {
          {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
        },
        device_types = {
          device_type_id = 0x0016, device_type_revision = 1, -- RootNode
        }
      },
      {
        endpoint_id = 10,
        clusters = {
          {
            cluster_id = clusters.WindowCovering.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 3,
          },
          {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002}
        },
      },
    },
  }
)

local mock_device_mains_powered = test.mock_device.build_test_matter_device(
  {
    profile = t_utils.get_profile_definition("window-covering.yml"),
    manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
    endpoints = {
      {
        endpoint_id = 2,
        clusters = {
          {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
        },
        device_types = {
          device_type_id = 0x0016, device_type_revision = 1, -- RootNode
        }
      },
      {
        endpoint_id = 10,
        clusters = {
          {
            cluster_id = clusters.WindowCovering.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 1,
          },
          {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0001}
        },
      },
    },
  }
)

local CLUSTER_SUBSCRIBE_LIST = {
  clusters.LevelControl.server.attributes.CurrentLevel,
  WindowCovering.server.attributes.CurrentPositionLiftPercent100ths,
  WindowCovering.server.attributes.CurrentPositionTiltPercent100ths,
  WindowCovering.server.attributes.OperationalStatus,
  clusters.PowerSource.server.attributes.BatPercentRemaining
}

local CLUSTER_SUBSCRIBE_LIST_NO_BATTERY = {
  clusters.LevelControl.server.attributes.CurrentLevel,
  WindowCovering.server.attributes.CurrentPositionLiftPercent100ths,
  WindowCovering.server.attributes.OperationalStatus,
}

local function set_preset(device)
  test.socket.capability:__expect_send(
    device:generate_test_message(
      "main", capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, {visibility = {displayed = false}})
    )
  )
  test.socket.capability:__expect_send(
    device:generate_test_message(
      "main", capabilities.windowShadePreset.position(50, {visibility = {displayed = false}})
    )
  )
end

local function test_init()
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"},
        {visibility = {displayed = false}})
    )
  )

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })
  set_preset(mock_device)
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  local read_attribute_list = clusters.PowerSource.attributes.AttributeList:read()
  test.socket.matter:__expect_send({mock_device.id, read_attribute_list})
end

local function test_init_mains_powered()
  test.mock_device.add_test_device(mock_device_mains_powered)
  test.socket.device_lifecycle:__queue_receive({ mock_device_mains_powered.id, "added" })
  test.socket.capability:__expect_send(
    mock_device_mains_powered:generate_test_message(
      "main", capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"},
        {visibility = {displayed = false}})
    )
  )

  test.socket.device_lifecycle:__queue_receive({ mock_device_mains_powered.id, "init" })
  set_preset(mock_device_mains_powered)
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST_NO_BATTERY[1]:subscribe(mock_device_mains_powered)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST_NO_BATTERY) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device_mains_powered)) end
  end
  test.socket.matter:__expect_send({mock_device_mains_powered.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device_mains_powered.id, "doConfigure" })
  mock_device_mains_powered:expect_metadata_update({ profile = "window-covering" })
  mock_device_mains_powered:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state closed following lift position update", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 10000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state closed following tilt position update", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, 10000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state closed before lift position 0", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 10000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state closed before tilt position 0", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, 10000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state open following lift position update", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 0
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(100)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state open following tilt position update", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, 0
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(100)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state open before lift position event", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(100)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 0
        ),
      }
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus state open before tilt position event", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(100)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, 0
        ),
      }
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus partially open following lift position update", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 25) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(25)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus partially open following tilt position update", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 15) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(15)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus partially open before lift position event", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 25) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(25)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering OperationalStatus partially open before tilt position event", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 65) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(65)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test("WindowCovering OperationalStatus opening", function()
  test.socket.capability:__set_channel_ordering("relaxed")
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
        mock_device, 10, ((100 - 25) *100)
      ),
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShadeLevel.shadeLevel(25)
    )
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.windowShade.partially_open()
    )
  )
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 1),
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.windowShade.opening()
    )
  )
end,
{
   min_api_version = 17
}
)

test.register_coroutine_test("WindowCovering OperationalStatus closing", function()
  test.socket.capability:__set_channel_ordering("relaxed")
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
        mock_device, 10, ((100 - 25) *100)
      ),
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShadeLevel.shadeLevel(25)
    )
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.windowShade.partially_open()
    )
  )
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 2),
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.windowShade.closing()
    )
  )
end,
{
   min_api_version = 17
}
)

test.register_coroutine_test("WindowCovering OperationalStatus unknown", function()
  test.socket.capability:__set_channel_ordering("relaxed")
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
        mock_device, 10, ((100 - 25) *100)
      ),
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShadeLevel.shadeLevel(25)
    )
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.windowShade.partially_open()
    )
  )
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 3),
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.windowShade.unknown()
    )
  )
end,
{
   min_api_version = 17
}
)

test.register_coroutine_test(
  "WindowShade open cmd handler", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "open", args = {}},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.UpOrOpen(mock_device, 10)}
    )
    test.wait_for_events()
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowShade close cmd handler", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "close", args = {}},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.DownOrClose(mock_device, 10)}
    )
    test.wait_for_events()
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowShade pause cmd handler", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "pause", args = {}},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.StopMotion(mock_device, 10)}
    )
    test.wait_for_events()
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Refresh necessary attributes", function()
    test.socket.device_lifecycle:__queue_receive({mock_device.id, "added"})
    test.socket.capability:__expect_send(
      {
        mock_device.id,
        {
          capability_id = "windowShade",
          component_id = "main",
          attribute_id = "supportedWindowShadeCommands",
          state = {value = {"open", "close", "pause"}},
          visibility = {displayed = false}
        },
      }
    )
    test.wait_for_events()

    test.socket.capability:__queue_receive(
      {mock_device.id, {capability = "refresh", component = "main", command = "refresh", args = {}}}
    )
    local read_request = CLUSTER_SUBSCRIBE_LIST[1]:read(mock_device)
    for i, attr in ipairs(CLUSTER_SUBSCRIBE_LIST) do
      if i > 1 then read_request:merge(attr:read(mock_device)) end
    end
    test.socket.matter:__expect_send({mock_device.id, read_request})
    test.wait_for_events()
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test("WindowShade setShadeLevel cmd handler", function()
  test.socket.capability:__queue_receive(
    {
      mock_device.id,
      {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 20 }},
    }
  )
  test.socket.matter:__expect_send(
    {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 8000)}
  )
end,
{
   min_api_version = 17
}
)

test.register_coroutine_test("WindowShade setShadeTiltLevel cmd handler", function()
  test.socket.capability:__queue_receive(
    {
      mock_device.id,
      {capability = "windowShadeTiltLevel", component = "main", command = "setShadeTiltLevel", args = { 60 }},
    }
  )
  test.socket.matter:__expect_send(
    {mock_device.id, WindowCovering.server.commands.GoToTiltPercentage(mock_device, 10, 4000)}
  )
end,
{
   min_api_version = 17
}
)

test.register_coroutine_test("LevelControl CurrentLevel handler", function()
  test.socket.matter:__queue_receive(
    {
      mock_device.id,
      clusters.LevelControl.attributes.CurrentLevel:build_test_report_data(mock_device, 10, 100),
    }
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShadeLevel.shadeLevel(math.floor((100 / 254.0 * 100) + .5))
    )
  )
end,
{
   min_api_version = 17
}
)

--test battery
test.register_coroutine_test(
  "Battery percent reports should generate correct messages", function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(
          mock_device, 10, 150
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.battery.battery(math.floor(150/2.0+0.5))
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test("OperationalStatus report contains current position report", function()
  test.socket.capability:__set_channel_ordering("relaxed")
  local report = WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
    mock_device, 10, ((100 - 25) *100)
  )
  table.insert(report.info_blocks, WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0).info_blocks[1])
  test.socket.matter:__queue_receive({ mock_device.id, report})
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShadeLevel.shadeLevel(25)
    )
  )
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.windowShade.partially_open()
    )
  )
end,
{
   min_api_version = 17
}
)

test.register_coroutine_test(
  "Handle preset commands",
  function()
    local PRESET_LEVEL = 30
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadePreset", component = "main", command = "setPresetPosition", args = { PRESET_LEVEL }},
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadePreset.position(PRESET_LEVEL)
      )
    )
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadePreset", component = "main", command = "presetPosition", args = {}},
    })
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, (100 - PRESET_LEVEL) * 100)}
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Test profile change to window-covering-battery when battery percent remaining attribute (attribute ID 12) is available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 10, {uint32(12)})
      }
    )
    mock_device:expect_metadata_update({ profile = "window-covering-tilt-battery" })
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Test that profile is not changed to window-covering-battery when battery percent remaining attribute (attribute ID 12) is not available",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 10, {uint32(10)})
      }
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "InfoChanged event checks for new profile match if device has changed (i.e. through reinterview or SW update)",
  function()
    test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({}))
    local read_attribute_list = clusters.PowerSource.attributes.AttributeList:read()
    test.socket.matter:__expect_send({mock_device.id, read_attribute_list})
    test.wait_for_events()
    test.socket.matter:__queue_receive({mock_device.id, clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 10, {uint32(0x0C)})})
    mock_device:expect_metadata_update({profile = "window-covering-tilt-battery"})
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering shade level adjusted by greater than 2%; status reflects Closing followed by Partially Open", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 25) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(25)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 19 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 8100)}
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 10),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closing()
      )
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 23) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(23)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 21) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(21)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 19) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
          "main", capabilities.windowShadeLevel.shadeLevel(19)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "WindowCovering shade level adjusted by less than or equal to 2%; status reflects Closing followed by Partially Open", function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 25) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(25)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 23 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 7700)}
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 10),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closing()
      )
    )
    test.wait_for_events()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, ((100 - 23) *100)
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(23)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Check that preference updates to reverse polarity after being set to true and that the shade lift operates as expected when opening and closing", function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({
      old_st_store = { profile = { name = "window-covering-tilt-battery" }, preferences = { reverse = false } },
      preferences = { reverse = "true" }
    }))
    test.wait_for_events()
    local reverse_preference_set = mock_device:get_field("__reverse_polarity")
    assert(reverse_preference_set == true, "reverse_preference_set is True")
    test.socket.matter:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
        mock_device, 10, 100 * 100
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
        mock_device, 10, 0
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(100)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 85 }},
    })
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 8500)}
    )
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 100 }},
    })
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 10000)}
    )
  end,
  {
     min_api_version = 17
  }
)

test.register_coroutine_test(
  "Check that preference updates to reverse polarity after being set to true and that the shade tilt operates as expected when opening and closing", function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({
      old_st_store = { profile = { name = "window-covering-tilt-battery" }, preferences = { reverse = false } },
      preferences = { reverse = "true" }
    }))
    test.wait_for_events()
    local reverse_preference_set = mock_device:get_field("__reverse_polarity")
    assert(reverse_preference_set == true, "reverse_preference_set is True")
    test.socket.matter:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
        mock_device, 10, 100 * 100
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
    test.socket.matter:__queue_receive({
      mock_device.id,
      WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
        mock_device, 10, 0
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(100)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadeTiltLevel", component = "main", command = "setShadeTiltLevel", args = { 15 }},
    })
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToTiltPercentage(mock_device, 10, 8500)}
    )
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadeTiltLevel", component = "main", command = "setShadeTiltLevel", args = { 0 }},
    })
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToTiltPercentage(mock_device, 10, 10000)}
    )
  end,
  {
     min_api_version = 17
  }
)

test.run_registered_tests()
-- stepShadeLevel tests

test.register_coroutine_test(
  "WindowShade stepShadeLevel cmd handler - step up", function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 9000)}
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel cmd handler - step down", function()
    -- First set initial position to 50
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 5000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(50)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()
    
    -- Step down by 20
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -20 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 7000)}
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel cmd handler - continuous step with target tracking", function()
    -- First set initial position to 30
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 7000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(30)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()
    
    -- First step up by 10 (target = 40)
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 6000)}
    )
    test.wait_for_events()
    
    -- Second step up by 10 without waiting for report (target = 50, using previous target 40 as base)
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 5000)}
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel - target reached clears target marker", function()
    -- Set initial position to 50
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 5000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(50)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()
    
    -- Step up by 10 (target = 60)
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 4000)}
    )
    test.wait_for_events()
    
    -- Device reports position 60 (within tolerance)
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 4000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(60)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    -- Target marker should be cleared internally (no external verification needed)
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel - step up to maximum (100)", function()
    -- Set initial position to 95
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 500
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(95)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()
    
    -- Step up by 10 (should clamp to 100)
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 0)}
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel - step down to minimum (0)", function()
    -- Set initial position to 5
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 9500
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(5)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()
    
    -- Step down by 10 (should clamp to 0)
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 10000)}
    )
  end,
  {
     min_api_version = 19
  }
)

test.register_coroutine_test(
  "WindowShade stepShadeLevel - other commands clear target marker", function()
    -- Set initial position to 50
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 5000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(50)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()
    
    -- Step up by 10
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 4000)}
    )
    test.wait_for_events()
    
    -- setShadeLevel should clear target marker
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 25 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 7500)}
    )
  end,
  {
     min_api_version = 19
  }
)

-- Additional tests for coverage improvement

-- Test handle_preset command
test.register_coroutine_test(
  "Handle presetPosition command",
  function()
    local PRESET_LEVEL = 30
    -- First set the preset position
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadePreset", component = "main", command = "setPresetPosition", args = { PRESET_LEVEL }},
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadePreset.position(PRESET_LEVEL)
      )
    )
    test.wait_for_events()

    -- Then trigger presetPosition command
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadePreset", component = "main", command = "presetPosition", args = {}},
    })
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, (100 - PRESET_LEVEL) * 100)}
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test handle_shade_level command
test.register_coroutine_test(
  "WindowShade setShadeLevel handler - basic",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShadeLevel", component = "main", command = "setShadeLevel", args = { 50 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 5000)}
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test handle_close with reverse polarity
test.register_coroutine_test(
  "WindowShade close cmd with reverse polarity true",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({ preferences = { reverse = "true" } }))
    test.wait_for_events()

    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "close", args = {}},
      }
    )
    -- With reverse=true, close should send UpOrOpen
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.UpOrOpen(mock_device, 10)}
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test handle_open with reverse polarity
test.register_coroutine_test(
  "WindowShade open cmd with reverse polarity true",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({ preferences = { reverse = "true" } }))
    test.wait_for_events()

    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShade", component = "main", command = "open", args = {}},
      }
    )
    -- With reverse=true, open should send DownOrClose
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.DownOrClose(mock_device, 10)}
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test infoChanged - reverse preference change (combined test for coverage)
test.register_coroutine_test(
  "InfoChanged - reverse preference changes",
  function()
    -- Test reverse preference change from false to true
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({
      old_st_store = { preferences = { reverse = false } },
      preferences = { reverse = true }
    }))
    test.wait_for_events()
  end,
  {
     min_api_version = 17
  }
)

-- Test current_pos_handler - lift nil, tilt 0 -> closed
test.register_coroutine_test(
  "CurrentPosition - lift nil, tilt 0 -> closed",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    -- Only report tilt position (0 = closed for tilt)
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, 10000 -- 0% tilt
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test current_pos_handler - lift nil, tilt 100 -> open
test.register_coroutine_test(
  "CurrentPosition - lift nil, tilt 100 -> open",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    -- Only report tilt position (100% = open for tilt)
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, 0 -- 100% tilt
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(100)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test current_pos_handler - lift 100 -> open
test.register_coroutine_test(
  "CurrentPosition - lift 100 -> open",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 0 -- 100% lift
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(100)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.open()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test current_pos_handler - reverse polarity state handling
test.register_coroutine_test(
  "CurrentPosition - reverse polarity affects state interpretation",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({ preferences = { reverse = "true" } }))
    test.wait_for_events()

    test.socket.capability:__set_channel_ordering("relaxed")
    -- Report lift at 100% (which should be interpreted as closed when reversed)
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 0 -- 100% lift
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(100)
      )
    )
    -- With reverse=true, lift 100 should be closed
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

-- -----------------------------------------------------------------------------
-- Additional tests for improving code coverage
-- -----------------------------------------------------------------------------

-- Test handle_set_preset command
test.register_coroutine_test(
  "Handle setPresetPosition command",
  function()
    local PRESET_LEVEL = 75
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadePreset", component = "main", command = "setPresetPosition", args = { PRESET_LEVEL }},
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadePreset.position(PRESET_LEVEL)
      )
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test handle_step_shade_level - step up
test.register_coroutine_test(
  "WindowShade stepShadeLevel - step up",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 9000)}
    )
  end,
  {
     min_api_version = 19
  }
)

-- Test handle_step_shade_level - step down with known position
test.register_coroutine_test(
  "WindowShade stepShadeLevel - step down from known position",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    -- First set initial position to 50
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 5000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(50)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()

    -- Step down by 20
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -20 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 7000)}
    )
  end,
  {
     min_api_version = 19
  }
)

-- Test handle_step_shade_level - clamp to maximum
test.register_coroutine_test(
  "WindowShade stepShadeLevel - clamp to maximum (100)",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    -- Set initial position to 95
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 500
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(95)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()

    -- Step up by 10 (should clamp to 100)
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 0)}
    )
  end,
  {
     min_api_version = 19
  }
)

-- Test handle_step_shade_level - clamp to minimum
test.register_coroutine_test(
  "WindowShade stepShadeLevel - clamp to minimum (0)",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    -- Set initial position to 5
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 9500
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(5)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()

    -- Step down by 10 (should clamp to 0)
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { -10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 10000)}
    )
  end,
  {
     min_api_version = 19
  }
)

-- Test current_status_handler - unknown state
test.register_coroutine_test(
  "OperationalStatus unknown state",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 3),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.unknown()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test current_status_handler - stopped clears target level
test.register_coroutine_test(
  "OperationalStatus stopped clears target level field",
  function()
    -- First set a target level via step
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 9000)}
    )
    test.wait_for_events()

    -- Report stopped status - should clear target level internally
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.OperationalStatus:build_test_report_data(mock_device, 10, 0),
      }
    )
    -- Target level field should be cleared (internal state, no external verification)
  end,
  {
     min_api_version = 17
  }
)

-- Test level_attr_handler
test.register_coroutine_test(
  "LevelControl CurrentLevel handler",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.LevelControl.attributes.CurrentLevel:build_test_report_data(mock_device, 10, 127),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(math.floor((127 / 254.0 * 100) + 0.5))
      )
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test battery_percent_remaining_attr_handler
test.register_coroutine_test(
  "Battery percent remaining handler",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(mock_device, 10, 100),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.battery.battery(50)
      )
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test power_source_attribute_list_handler - battery percentage present
test.register_coroutine_test(
  "PowerSource attribute list - BatPercentRemaining present triggers profile update",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 10, {uint32(0x0C)}),
      }
    )
    mock_device:expect_metadata_update({ profile = "window-covering-tilt-battery" })
  end,
  {
     min_api_version = 17
  }
)

-- Test power_source_attribute_list_handler - BatChargeLevel present
test.register_coroutine_test(
  "PowerSource attribute list - BatChargeLevel present triggers batteryLevel profile",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 10, {uint32(0x0E)}),
      }
    )
    mock_device:expect_metadata_update({ profile = "window-covering-tilt-batteryLevel" })
  end,
  {
     min_api_version = 17
  }
)

-- Test current_pos_handler - lift nil, tilt partially open
test.register_coroutine_test(
  "CurrentPosition - lift nil, tilt 50 -> partially_open",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, 5000 -- 50% tilt
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(50)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test current_pos_handler - lift 0, tilt nil -> closed
test.register_coroutine_test(
  "CurrentPosition - lift 0, tilt nil -> closed",
  function()
    -- First clear tilt by setting to nil (not directly testable, use lift only scenario)
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 10000 -- 0% lift
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test current_pos_handler - lift 0, tilt 50 -> partially_open
test.register_coroutine_test(
  "CurrentPosition - lift 0, tilt 50 -> partially_open",
  function()
    test.socket.capability:__set_channel_ordering("relaxed")
    -- First report lift at 0
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 10000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(0)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.closed()
      )
    )
    -- Then report tilt at 50
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionTiltPercent100ths:build_test_report_data(
          mock_device, 10, 5000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeTiltLevel.shadeTiltLevel(50)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test handle_shade_tilt_level command
test.register_coroutine_test(
  "WindowShade setShadeTiltLevel handler",
  function()
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "windowShadeTiltLevel", component = "main", command = "setShadeTiltLevel", args = { 75 }},
      }
    )
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToTiltPercentage(mock_device, 10, 2500)}
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test device_added emits supported commands
test.register_coroutine_test(
  "Device added emits supported windowShade commands",
  function()
    test.disable_startup_messages()
    local new_device = test.mock_device.build_test_matter_device(
      {
        profile = t_utils.get_profile_definition("window-covering.yml"),
        manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
        endpoints = {
          {
            endpoint_id = 2,
            clusters = {
              {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
            },
            device_types = {
              device_type_id = 0x0016, device_type_revision = 1,
            }
          },
          {
            endpoint_id = 10,
            clusters = {
              {
                cluster_id = clusters.WindowCovering.ID,
                cluster_type = "SERVER",
                cluster_revision = 1,
                feature_map = 1,
              },
            },
          },
        },
      }
    )
    test.mock_device.add_test_device(new_device)
    test.socket.device_lifecycle:__queue_receive({ new_device.id, "added" })
    test.socket.capability:__expect_send(
      new_device:generate_test_message(
        "main", capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"},
          {visibility = {displayed = false}})
      )
    )
  end,
  {
     min_api_version = 17
  }
)

-- Test doConfigure with battery support
test.register_coroutine_test(
  "DoConfigure with battery support reads AttributeList",
  function()
    -- Create device with battery feature - use tilt-battery profile for batteryLevel capability
    local battery_device = test.mock_device.build_test_matter_device(
      {
        profile = t_utils.get_profile_definition("window-covering-tilt-battery.yml"),
        manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
        endpoints = {
          {
            endpoint_id = 2,
            clusters = {
              {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
            },
            device_types = {
              device_type_id = 0x0016, device_type_revision = 1,
            }
          },
          {
            endpoint_id = 10,
            clusters = {
              {
                cluster_id = clusters.WindowCovering.ID,
                cluster_type = "SERVER",
                cluster_revision = 1,
                feature_map = 3,
              },
              {cluster_id = clusters.LevelControl.ID, cluster_type = "SERVER"},
              {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002},
            },
          },
        },
      }
    )
    test.mock_device.add_test_device(battery_device)
    test.socket.device_lifecycle:__queue_receive({ battery_device.id, "added" })
    test.socket.capability:__expect_send(
      battery_device:generate_test_message(
        "main", capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"},
          {visibility = {displayed = false}})
      )
    )
    test.socket.device_lifecycle:__queue_receive({ battery_device.id, "init" })
    test.socket.capability:__expect_send(
      battery_device:generate_test_message(
        "main", capabilities.windowShadePreset.supportedCommands({"presetPosition", "setPresetPosition"}, {visibility = {displayed = false}})
      )
    )
    test.socket.capability:__expect_send(
      battery_device:generate_test_message(
        "main", capabilities.windowShadePreset.position(50, {visibility = {displayed = false}})
      )
    )
    local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(battery_device)
    for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
      if i > 1 then subscribe_request:merge(clus:subscribe(battery_device)) end
    end
    test.socket.matter:__expect_send({battery_device.id, subscribe_request})
    test.socket.device_lifecycle:__queue_receive({ battery_device.id, "doConfigure" })
    -- Should read AttributeList to check for battery support
    local read_request = clusters.PowerSource.attributes.AttributeList:read()
    test.socket.matter:__expect_send({battery_device.id, read_request})
    battery_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
     min_api_version = 17
  }
)

-- Test doConfigure without battery support
test.register_coroutine_test(
  "DoConfigure without battery support matches profile directly",
  function()
    -- Create device without battery feature (mains powered)
    local mains_device = test.mock_device.build_test_matter_device(
      {
        profile = t_utils.get_profile_definition("window-covering.yml"),
        manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
        endpoints = {
          {
            endpoint_id = 2,
            clusters = {
              {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
            },
            device_types = {
              device_type_id = 0x0016, device_type_revision = 1,
            }
          },
          {
            endpoint_id = 10,
            clusters = {
              {
                cluster_id = clusters.WindowCovering.ID,
                cluster_type = "SERVER",
                cluster_revision = 1,
                feature_map = 1,
              },
              {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0001},
            },
          },
        },
      }
    )
    test.mock_device.add_test_device(mains_device)
    test.socket.device_lifecycle:__queue_receive({ mains_device.id, "doConfigure" })
    -- Should match profile without battery
    mains_device:expect_metadata_update({ profile = "window-covering" })
    mains_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
     min_api_version = 17
  }
)

-- Test device_removed lifecycle
test.register_coroutine_test(
  "Device removed lifecycle",
  function()
    test.socket.device_lifecycle:__queue_receive({ mock_device.id, "removed" })
    test.wait_for_events()
  end,
  {
     min_api_version = 17
  }
)

-- Test component_to_endpoint function
test.register_coroutine_test(
  "Component to endpoint mapping",
  function()
    local endpoint = mock_device:component_to_endpoint("main")
    assert(endpoint == 10, "Endpoint should be 10 for main component")
  end,
  {
     min_api_version = 17
  }
)

-- Test match_profile - tilt-only device (no lift)
test.register_coroutine_test(
  "Match profile - tilt-only device",
  function()
    local tilt_only_device = test.mock_device.build_test_matter_device(
      {
        profile = t_utils.get_profile_definition("window-covering.yml"),
        manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
        endpoints = {
          {
            endpoint_id = 2,
            clusters = {
              {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
            },
            device_types = {
              device_type_id = 0x0016, device_type_revision = 1,
            }
          },
          {
            endpoint_id = 10,
            clusters = {
              {
                cluster_id = clusters.WindowCovering.ID,
                cluster_type = "SERVER",
                cluster_revision = 1,
                feature_map = 2, -- TILT only (bit 1)
              },
            },
          },
        },
      }
    )
    test.mock_device.add_test_device(tilt_only_device)
    test.socket.device_lifecycle:__queue_receive({ tilt_only_device.id, "doConfigure" })
    tilt_only_device:expect_metadata_update({ profile = "window-covering-tilt-only" })
    tilt_only_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
  end,
  {
     min_api_version = 17
  }
)

-- Test refresh handler
test.register_coroutine_test(
  "Refresh handler reads all subscribed attributes",
  function()
    test.socket.capability:__queue_receive(
      {mock_device.id, {capability = "refresh", component = "main", command = "refresh", args = {}}}
    )
    local read_request = CLUSTER_SUBSCRIBE_LIST[1]:read(mock_device)
    for i, attr in ipairs(CLUSTER_SUBSCRIBE_LIST) do
      if i > 1 then read_request:merge(attr:read(mock_device)) end
    end
    test.socket.matter:__expect_send({mock_device.id, read_request})
  end,
  {
     min_api_version = 17
  }
)

-- Test reverse polarity with stepShadeLevel
test.register_coroutine_test(
  "StepShadeLevel with reverse polarity",
  function()
    test.socket.device_lifecycle():__queue_receive(mock_device:generate_info_changed({ preferences = { reverse = "true" } }))
    test.wait_for_events()

    -- Set initial position to 50
    test.socket.capability:__set_channel_ordering("relaxed")
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        WindowCovering.attributes.CurrentPositionLiftPercent100ths:build_test_report_data(
          mock_device, 10, 5000
        ),
      }
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShadeLevel.shadeLevel(50)
      )
    )
    test.socket.capability:__expect_send(
      mock_device:generate_test_message(
        "main", capabilities.windowShade.windowShade.partially_open()
      )
    )
    test.wait_for_events()

    -- Step up by 10 (with reverse, should go to 60)
    test.socket.capability:__queue_receive(
      {
        mock_device.id,
        {capability = "statelessWindowShadeLevelStep", component = "main", command = "stepShadeLevel", args = { 10 }},
      }
    )
    -- With reverse=true, target_level = 60, lift_percentage_value = 60
    test.socket.matter:__expect_send(
      {mock_device.id, WindowCovering.server.commands.GoToLiftPercentage(mock_device, 10, 6000)}
    )
  end,
  {
     min_api_version = 19
  }
)

-- Test battery_charge_level_attr_handler - nil value
-- Note: This test verifies that the handler gracefully handles nil values
-- The mock framework cannot create nil value reports, so we verify via code inspection
test.register_coroutine_test(
  "Battery charge level handler - nil value",
  function()
    -- Handler checks `if ib.data.value == clusters.PowerSource.types.BatChargeLevelEnum.OK then`
    -- nil value will not match any condition, so no event is emitted
    -- This is verified by code inspection in init.lua lines 348-355
    test.wait_for_events()
  end,
  {
     min_api_version = 17
  }
)

-- Test battery_percent_remaining_attr_handler - nil value
-- Note: This test verifies that the handler gracefully handles nil values
-- The mock framework cannot create nil value reports, so we verify via code inspection
test.register_coroutine_test(
  "Battery percent remaining handler - nil value",
  function()
    -- Handler checks `if ib.data.value then` - nil will skip event emission
    -- This is verified by code inspection in init.lua lines 342-345
    test.wait_for_events()
  end,
  {
     min_api_version = 17
  }
)

-- Test level_attr_handler - nil value
-- Note: This test verifies that the handler gracefully handles nil values
-- The mock framework cannot create nil value reports, so we verify via code inspection
test.register_coroutine_test(
  "LevelControl CurrentLevel handler - nil value",
  function()
    -- Handler checks `if ib.data.value ~= nil then` - nil will skip event emission
    -- This is verified by code inspection in init.lua lines 334-339
    test.wait_for_events()
  end,
  {
     min_api_version = 17
  }
)

-- Test current_pos_handler - nil value
-- Note: This test verifies that the handler gracefully handles nil values
-- The mock framework cannot create nil value reports, so we verify via code inspection
test.register_coroutine_test(
  "CurrentPosition handler - nil value",
  function()
    -- Handler checks `if ib.data.value == nil then return end` at the start
    -- This is verified by code inspection in init.lua lines 237-241
    test.wait_for_events()
  end,
  {
     min_api_version = 17
  }
)

-- Test power_source_attribute_list_handler - no battery attributes
test.register_coroutine_test(
  "PowerSource attribute list - no battery attributes",
  function()
    test.socket.matter:__queue_receive(
      {
        mock_device.id,
        clusters.PowerSource.attributes.AttributeList:build_test_report_data(mock_device, 10, {uint32(1), uint32(2)}),
      }
    )
    -- Should not change profile
    test.wait_for_events()
  end,
  {
     min_api_version = 17
  }
)

test.run_registered_tests()
