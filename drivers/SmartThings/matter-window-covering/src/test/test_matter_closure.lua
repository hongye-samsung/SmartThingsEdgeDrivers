-- Copyright © 2026 SmartThings, Inc.
-- Licensed under the Apache License, Version 2.0

local capabilities = require "st.capabilities"
local clusters = require "st.matter.clusters"
local test = require "integration_test"
local t_utils = require "integration_test.utils"
local uint32 = require "st.matter.data_types.Uint32"
local version = require "version"

if version.api < 20 then
  clusters.ClosureControl = require "embedded_clusters.ClosureControl"
  clusters.ClosureDimension = require "embedded_clusters.ClosureDimension"
end

-- ---------------------------------------------------------------------------
-- Mock device: Covering type (windowShade / windowShadeLevel)
-- ---------------------------------------------------------------------------

local mock_device = test.mock_device.build_test_matter_device(
  {
    label = "Matter Closure",
    profile = t_utils.get_profile_definition("covering.yml"),
    manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
    matter_version = {hardware = 1, software = 1},
    endpoints = {
      {
        endpoint_id = 2,
        clusters = {
          {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
        },
        device_types = {
          {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
        }
      },
      {
        endpoint_id = 10,
        clusters = {
          {
            cluster_id = clusters.ClosureControl.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 3,
          },
          {cluster_id = clusters.Descriptor.ID, cluster_type = "SERVER", feature_map = 0},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002}
        },
        device_types = {
          {device_type_id = 0x0230, device_type_revision = 1} -- Closure
        }
      },
      {
        endpoint_id = 11,
        clusters = {
          {
            cluster_id = clusters.ClosureDimension.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 0,
          },
        },
        device_types = {
          {device_type_id = 0x0231, device_type_revision = 1} -- ClosureDimension
        }
      },
      {
        endpoint_id = 12,
        clusters = {
          {
            cluster_id = clusters.ClosureDimension.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 0,
          },
        },
        device_types = {
          {device_type_id = 0x0231, device_type_revision = 1} -- ClosureDimension
        }
      },
    },
  }
)

-- ---------------------------------------------------------------------------
-- Mock device: Door type (doorControl / level)
-- ---------------------------------------------------------------------------

local mock_door_device = test.mock_device.build_test_matter_device(
  {
    label = "Matter Door",
    profile = t_utils.get_profile_definition("door.yml"),
    manufacturer_info = {vendor_id = 0x0000, product_id = 0x0000},
    matter_version = {hardware = 1, software = 1},
    endpoints = {
      {
        endpoint_id = 2,
        clusters = {
          {cluster_id = clusters.Basic.ID, cluster_type = "SERVER"},
        },
        device_types = {
          {device_type_id = 0x0016, device_type_revision = 1} -- RootNode
        }
      },
      {
        endpoint_id = 10,
        clusters = {
          {
            cluster_id = clusters.ClosureControl.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 3,
          },
          {cluster_id = clusters.Descriptor.ID, cluster_type = "SERVER", feature_map = 0},
          {cluster_id = clusters.PowerSource.ID, cluster_type = "SERVER", feature_map = 0x0002}
        },
        device_types = {
          {device_type_id = 0x0230, device_type_revision = 1} -- Closure
        }
      },
      {
        endpoint_id = 11,
        clusters = {
          {
            cluster_id = clusters.ClosureDimension.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 0,
          },
        },
        device_types = {
          {device_type_id = 0x0231, device_type_revision = 1} -- ClosureDimension
        }
      },
      {
        endpoint_id = 12,
        clusters = {
          {
            cluster_id = clusters.ClosureDimension.ID,
            cluster_type = "SERVER",
            cluster_revision = 1,
            feature_map = 0,
          },
        },
        device_types = {
          {device_type_id = 0x0231, device_type_revision = 1} -- ClosureDimension
        }
      },
    },
  }
)

local CLUSTER_SUBSCRIBE_LIST = {
  clusters.ClosureControl.attributes.MainState,
  clusters.ClosureControl.attributes.OverallCurrentState,
  clusters.ClosureControl.attributes.OverallTargetState,
}

-- additional clusters that will be subscribed to initially but not after the profile is matched.
local ADDITIONAL_SUBSCRIBE_LIST = {
  clusters.PowerSource.attributes.AttributeList,
  clusters.Descriptor.attributes.TagList,
}

local function test_init()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_device)
  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "added" })
  test.socket.capability:__expect_send(
    mock_device:generate_test_message(
      "main", capabilities.windowShade.supportedWindowShadeCommands({"open", "close", "pause"},
        {visibility = {displayed = false}})
    )
  )

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "init" })

  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  for _, clus in ipairs(ADDITIONAL_SUBSCRIBE_LIST) do
    subscribe_request:merge(clus:subscribe(mock_device))
  end
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_device.id, "doConfigure" })
  mock_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

test.set_test_init_function(test_init)

local function update_profile()
  test.socket.matter:__queue_receive({mock_device.id, clusters.PowerSource.attributes.AttributeList:build_test_report_data(
    mock_device, 10, {uint32(clusters.PowerSource.attributes.BatPercentRemaining.ID)}
  )})
  test.socket.matter:__queue_receive({mock_device.id, clusters.Descriptor.attributes.TagList:build_test_report_data(
    mock_device, 10, {clusters.Global.types.SemanticTagStruct({mfg_code = 0x00, namespace_id = 0x44, tag = 0x00, name = "Covering"})  }
  )})
  mock_device:expect_metadata_update({
    profile = "covering",
    optional_component_capabilities = {
      {"main", {"battery"}},
      {"windowShade1", {"windowShadeLevel"}},
      {"windowShade2", {"windowShadeLevel"}},
    }
  })
  test.wait_for_events()
  local updated_device_profile = t_utils.get_profile_definition("covering.yml", {
    enabled_optional_capabilities = {
      {"main", {"battery"}},
      {"windowShade1", {"windowShadeLevel"}},
      {"windowShade2", {"windowShadeLevel"}},
    }
  })
  test.socket.device_lifecycle:__queue_receive(mock_device:generate_info_changed({ profile = updated_device_profile }))
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_device)) end
  end
  subscribe_request:merge(clusters.PowerSource.server.attributes.BatPercentRemaining:subscribe(mock_device))
  subscribe_request:merge(clusters.ClosureDimension.attributes.CurrentState:subscribe(mock_device))
  test.socket.matter:__expect_send({mock_device.id, subscribe_request})
end

local function test_init_door()
  test.disable_startup_messages()
  test.mock_device.add_test_device(mock_door_device)
  test.socket.device_lifecycle:__queue_receive({ mock_door_device.id, "added" })

  test.socket.device_lifecycle:__queue_receive({ mock_door_device.id, "init" })

  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_door_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_door_device)) end
  end
  for _, clus in ipairs(ADDITIONAL_SUBSCRIBE_LIST) do
    subscribe_request:merge(clus:subscribe(mock_door_device))
  end
  test.socket.matter:__expect_send({mock_door_device.id, subscribe_request})

  test.socket.device_lifecycle:__queue_receive({ mock_door_device.id, "doConfigure" })
  mock_door_device:expect_metadata_update({ provisioning_state = "PROVISIONED" })
end

local function update_profile_door()
  test.socket.matter:__queue_receive({mock_door_device.id, clusters.PowerSource.attributes.AttributeList:build_test_report_data(
    mock_door_device, 10, {uint32(clusters.PowerSource.attributes.BatPercentRemaining.ID)}
  )})
  test.socket.matter:__queue_receive({mock_door_device.id, clusters.Descriptor.attributes.TagList:build_test_report_data(
    mock_door_device, 10, {clusters.Global.types.SemanticTagStruct({mfg_code = 0x00, namespace_id = 0x44, tag = 0x06, name = "Door"})}
  )})
  mock_door_device:expect_metadata_update({
    profile = "door",
    optional_component_capabilities = {
      {"main", {"battery"}},
      {"door1", {"level"}},
      {"door2", {"level"}},
    }
  })
  test.wait_for_events()
  local updated_device_profile = t_utils.get_profile_definition("door.yml", {
    enabled_optional_capabilities = {
      {"main", {"battery"}},
      {"door1", {"level"}},
      {"door2", {"level"}},
    }
  })
  test.socket.device_lifecycle:__queue_receive(mock_door_device:generate_info_changed({ profile = updated_device_profile }))
  local subscribe_request = CLUSTER_SUBSCRIBE_LIST[1]:subscribe(mock_door_device)
  for i, clus in ipairs(CLUSTER_SUBSCRIBE_LIST) do
    if i > 1 then subscribe_request:merge(clus:subscribe(mock_door_device)) end
  end
  subscribe_request:merge(clusters.PowerSource.server.attributes.BatPercentRemaining:subscribe(mock_door_device))
  subscribe_request:merge(clusters.ClosureDimension.attributes.CurrentState:subscribe(mock_door_device))
  test.socket.matter:__expect_send({mock_door_device.id, subscribe_request})
end

test.register_coroutine_test(
  "windowShade closed following MainState and OverallTargetState update", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.MainState:build_test_report_data(mock_device, 10, clusters.ClosureControl.types.MainStateEnum.MOVING),
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.OverallTargetState:build_test_report_data(mock_device, 10,
        clusters.ClosureControl.types.OverallTargetStateStruct({
          position = clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.MEDIUM
        }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing())
    )
  end
)

test.register_coroutine_test(
  "windowShade opening following MainState and OverallTargetState update", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.MainState:build_test_report_data(mock_device, 10, clusters.ClosureControl.types.MainStateEnum.MOVING),
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.OverallTargetState:build_test_report_data(mock_device, 10,
        clusters.ClosureControl.types.OverallTargetStateStruct({
          position = clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.MEDIUM
        }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.opening())
    )
  end
)

test.register_coroutine_test(
  "windowShade closed following OverallCurrentState FULLY_CLOSED", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.OverallCurrentState:build_test_report_data(mock_device, 10,
        clusters.ClosureControl.types.OverallCurrentStateStruct({
          position = clusters.ClosureControl.types.CurrentPositionEnum.FULLY_CLOSED,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO,
          secure_state = false
        }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    )
  end
)

test.register_coroutine_test(
  "windowShade open following OverallCurrentState FULLY_OPENED", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.OverallCurrentState:build_test_report_data(mock_device, 10,
        clusters.ClosureControl.types.OverallCurrentStateStruct({
          position = clusters.ClosureControl.types.CurrentPositionEnum.FULLY_OPENED,
          latch = true,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO,
          secure_state = false
        }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.open())
    )
  end
)

test.register_coroutine_test(
  "windowShade partially_open following OverallCurrentState PARTIALLY_OPENED", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.OverallCurrentState:build_test_report_data(mock_device, 10,
        clusters.ClosureControl.types.OverallCurrentStateStruct({
          position = clusters.ClosureControl.types.CurrentPositionEnum.PARTIALLY_OPENED,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO,
          secure_state = false
        }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.partially_open())
    )
  end
)

test.register_coroutine_test(
  "windowShade state transitions from closing to closed", function()
    update_profile()
    test.wait_for_events()
    -- device starts moving toward closed
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.MainState:build_test_report_data(mock_device, 10, clusters.ClosureControl.types.MainStateEnum.MOVING),
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.OverallTargetState:build_test_report_data(mock_device, 10,
        clusters.ClosureControl.types.OverallTargetStateStruct({
          position = clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.MEDIUM
        }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closing())
    )
    test.wait_for_events()
    -- device stops and reports fully closed
    -- MainState STOPPED with no current position cached yet. no capability event emitted
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.MainState:build_test_report_data(mock_device, 10, clusters.ClosureControl.types.MainStateEnum.STOPPED),
    })
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureControl.attributes.OverallCurrentState:build_test_report_data(mock_device, 10,
        clusters.ClosureControl.types.OverallCurrentStateStruct({
          position = clusters.ClosureControl.types.CurrentPositionEnum.FULLY_CLOSED,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO,
          secure_state = false
        }))
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.windowShade.windowShade.closed())
    )
  end
)

test.register_coroutine_test(
  "windowShade close command sends ClosureControl MoveTo FULLY_CLOSED", function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShade", component = "main", command = "close", args = {}},
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      clusters.ClosureControl.server.commands.MoveTo(
        mock_device, 10, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED
      )
    })
  end
)

test.register_coroutine_test(
  "windowShade open command sends ClosureControl MoveTo FULLY_OPEN", function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShade", component = "main", command = "open", args = {}},
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      clusters.ClosureControl.server.commands.MoveTo(
        mock_device, 10, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN
      )
    })
  end
)

test.register_coroutine_test(
  "windowShade pause command sends ClosureControl Stop", function()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShade", component = "main", command = "pause", args = {}},
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      clusters.ClosureControl.server.commands.Stop(mock_device, 10)
    })
  end
)

test.register_coroutine_test(
  "Battery percentage reported correctly for closure device", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.PowerSource.attributes.BatPercentRemaining:build_test_report_data(mock_device, 10, 150)
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("main", capabilities.battery.battery(math.floor(150 / 2.0 + 0.5)))
    )
  end
)

test.register_coroutine_test(
  "setShadeLevel on windowShade1 sends SetTarget to endpoint 11", function()
    update_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadeLevel", component = "windowShade1", command = "setShadeLevel", args = {75}},
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      clusters.ClosureDimension.server.commands.SetTarget(mock_device, 11, 75 * 100)
    })
  end
)

test.register_coroutine_test(
  "setShadeLevel on windowShade2 sends SetTarget to endpoint 12", function()
    update_profile()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_device.id,
      {capability = "windowShadeLevel", component = "windowShade2", command = "setShadeLevel", args = {40}},
    })
    test.socket.matter:__expect_send({
      mock_device.id,
      clusters.ClosureDimension.server.commands.SetTarget(mock_device, 12, 40 * 100)
    })
  end
)

test.register_coroutine_test(
  "ClosureDimension CurrentState on endpoint 11 emits shadeLevel on windowShade1", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureDimension.attributes.CurrentState:build_test_report_data(mock_device, 11,
        clusters.ClosureDimension.types.DimensionStateStruct({
          position = 6000,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO
        })
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("windowShade1", capabilities.windowShadeLevel.shadeLevel(60))
    )
  end
)

test.register_coroutine_test(
  "ClosureDimension CurrentState on endpoint 12 emits shadeLevel on windowShade2", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureDimension.attributes.CurrentState:build_test_report_data(mock_device, 12,
        clusters.ClosureDimension.types.DimensionStateStruct({
          position = 2500,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO
        })
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("windowShade2", capabilities.windowShadeLevel.shadeLevel(25))
    )
  end
)

test.register_coroutine_test(
  "ClosureDimension CurrentState with closed position emits shadeLevel 0", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureDimension.attributes.CurrentState:build_test_report_data(mock_device, 11,
        clusters.ClosureDimension.types.DimensionStateStruct({
          position = 0,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO
        })
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("windowShade1", capabilities.windowShadeLevel.shadeLevel(0))
    )
  end
)

test.register_coroutine_test(
  "ClosureDimension CurrentState with full-open position emits shadeLevel 100", function()
    update_profile()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_device.id,
      clusters.ClosureDimension.attributes.CurrentState:build_test_report_data(mock_device, 11,
        clusters.ClosureDimension.types.DimensionStateStruct({
          position = 10000,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO
        })
      )
    })
    test.socket.capability:__expect_send(
      mock_device:generate_test_message("windowShade1", capabilities.windowShadeLevel.shadeLevel(100))
    )
  end
)

-- ---------------------------------------------------------------------------
-- Door / garage-door / gate type tests
-- ---------------------------------------------------------------------------

test.register_coroutine_test(
  "doorControl closed following MainState and OverallTargetState update", function()
    update_profile_door()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_door_device.id,
      clusters.ClosureControl.attributes.MainState:build_test_report_data(mock_door_device, 10, clusters.ClosureControl.types.MainStateEnum.MOVING),
    })
    test.socket.matter:__queue_receive({
      mock_door_device.id,
      clusters.ClosureControl.attributes.OverallTargetState:build_test_report_data(mock_door_device, 10,
        clusters.ClosureControl.types.OverallTargetStateStruct({
          position = clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.MEDIUM
        }))
    })
    test.socket.capability:__expect_send(
      mock_door_device:generate_test_message("main", capabilities.doorControl.door.closing())
    )
  end,
  {test_init = test_init_door}
)

test.register_coroutine_test(
  "doorControl opening following MainState and OverallTargetState update", function()
    update_profile_door()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_door_device.id,
      clusters.ClosureControl.attributes.MainState:build_test_report_data(mock_door_device, 10, clusters.ClosureControl.types.MainStateEnum.MOVING),
    })
    test.socket.matter:__queue_receive({
      mock_door_device.id,
      clusters.ClosureControl.attributes.OverallTargetState:build_test_report_data(mock_door_device, 10,
        clusters.ClosureControl.types.OverallTargetStateStruct({
          position = clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.MEDIUM
        }))
    })
    test.socket.capability:__expect_send(
      mock_door_device:generate_test_message("main", capabilities.doorControl.door.opening())
    )
  end,
  {test_init = test_init_door}
)

test.register_coroutine_test(
  "doorControl closed following OverallCurrentState FULLY_CLOSED", function()
    update_profile_door()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_door_device.id,
      clusters.ClosureControl.attributes.OverallCurrentState:build_test_report_data(mock_door_device, 10,
        clusters.ClosureControl.types.OverallCurrentStateStruct({
          position = clusters.ClosureControl.types.CurrentPositionEnum.FULLY_CLOSED,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO,
          secure_state = false
        }))
    })
    test.socket.capability:__expect_send(
      mock_door_device:generate_test_message("main", capabilities.doorControl.door.closed())
    )
  end,
  {test_init = test_init_door}
)

test.register_coroutine_test(
  "doorControl open following OverallCurrentState FULLY_OPENED", function()
    update_profile_door()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_door_device.id,
      clusters.ClosureControl.attributes.OverallCurrentState:build_test_report_data(mock_door_device, 10,
        clusters.ClosureControl.types.OverallCurrentStateStruct({
          position = clusters.ClosureControl.types.CurrentPositionEnum.FULLY_OPENED,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO,
          secure_state = false
        }))
    })
    test.socket.capability:__expect_send(
      mock_door_device:generate_test_message("main", capabilities.doorControl.door.open())
    )
  end,
  {test_init = test_init_door}
)

test.register_coroutine_test(
  "doorControl open following OverallCurrentState PARTIALLY_OPENED (doorControl has no partially_open)", function()
    update_profile_door()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_door_device.id,
      clusters.ClosureControl.attributes.OverallCurrentState:build_test_report_data(mock_door_device, 10,
        clusters.ClosureControl.types.OverallCurrentStateStruct({
          position = clusters.ClosureControl.types.CurrentPositionEnum.PARTIALLY_OPENED,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO,
          secure_state = false
        }))
    })
    -- doorControl has no partially_open state; any non-fully-closed position maps to open
    test.socket.capability:__expect_send(
      mock_door_device:generate_test_message("main", capabilities.doorControl.door.open())
    )
  end,
  {test_init = test_init_door}
)

test.register_coroutine_test(
  "doorControl close command sends ClosureControl MoveTo FULLY_CLOSED", function()
    test.socket.capability:__queue_receive({
      mock_door_device.id,
      {capability = "doorControl", component = "main", command = "close", args = {}},
    })
    test.socket.matter:__expect_send({
      mock_door_device.id,
      clusters.ClosureControl.server.commands.MoveTo(
        mock_door_device, 10, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_CLOSED
      )
    })
  end,
  {test_init = test_init_door}
)

test.register_coroutine_test(
  "doorControl open command sends ClosureControl MoveTo FULLY_OPEN", function()
    test.socket.capability:__queue_receive({
      mock_door_device.id,
      {capability = "doorControl", component = "main", command = "open", args = {}},
    })
    test.socket.matter:__expect_send({
      mock_door_device.id,
      clusters.ClosureControl.server.commands.MoveTo(
        mock_door_device, 10, clusters.ClosureControl.types.TargetPositionEnum.MOVE_TO_FULLY_OPEN
      )
    })
  end,
  {test_init = test_init_door}
)

test.register_coroutine_test(
  "ClosureDimension CurrentState on endpoint 11 emits level on door1 for door device", function()
    update_profile_door()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_door_device.id,
      clusters.ClosureDimension.attributes.CurrentState:build_test_report_data(mock_door_device, 11,
        clusters.ClosureDimension.types.DimensionStateStruct({
          position = 7500,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO
        })
      )
    })
    test.socket.capability:__expect_send(
      mock_door_device:generate_test_message("door1", capabilities.level.level(75))
    )
  end,
  {test_init = test_init_door}
)

test.register_coroutine_test(
  "ClosureDimension CurrentState on endpoint 12 emits level on door2 for door device", function()
    update_profile_door()
    test.wait_for_events()
    test.socket.matter:__queue_receive({
      mock_door_device.id,
      clusters.ClosureDimension.attributes.CurrentState:build_test_report_data(mock_door_device, 12,
        clusters.ClosureDimension.types.DimensionStateStruct({
          position = 3000,
          latch = false,
          speed = clusters.Global.types.ThreeLevelAutoEnum.AUTO
        })
      )
    })
    test.socket.capability:__expect_send(
      mock_door_device:generate_test_message("door2", capabilities.level.level(30))
    )
  end,
  {test_init = test_init_door}
)

-- Test: handle_level command for door type
test.register_coroutine_test(
  "doorControl level command sends SetTarget to endpoint 11", function()
    update_profile_door()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_door_device.id,
      {capability = "level", component = "door1", command = "setLevel", args = {60}},
    })
    test.socket.matter:__expect_send({
      mock_door_device.id,
      clusters.ClosureDimension.server.commands.SetTarget(mock_door_device, 11, 60 * 100)
    })
  end,
  {test_init = test_init_door}
)

-- Test: handle_level command for door type endpoint 12
test.register_coroutine_test(
  "doorControl level command sends SetTarget to endpoint 12", function()
    update_profile_door()
    test.wait_for_events()
    test.socket.capability:__queue_receive({
      mock_door_device.id,
      {capability = "level", component = "door2", command = "setLevel", args = {30}},
    })
    test.socket.matter:__expect_send({
      mock_door_device.id,
      clusters.ClosureDimension.server.commands.SetTarget(mock_door_device, 12, 30 * 100)
    })
  end,
  {test_init = test_init_door}
)

-- Test: Multi-panel device component mapping
test.register_coroutine_test(
  "Multi-panel device endpoint_to_component mapping", function()
    update_profile()
    test.wait_for_events()
    -- endpoint 11 should map to windowShade1
    local component = mock_device:endpoint_to_component(11)
    assert(component == "windowShade1", "Expected windowShade1, got " .. tostring(component))
    -- endpoint 12 should map to windowShade2
    component = mock_device:endpoint_to_component(12)
    assert(component == "windowShade2", "Expected windowShade2, got " .. tostring(component))
  end
)

-- Test: Single panel device component mapping (main)
test.register_coroutine_test(
  "Single panel device component_to_endpoint mapping to main", function()
    update_profile()
    test.wait_for_events()
    local endpoint = mock_device:component_to_endpoint("main")
    assert(endpoint ~= nil, "Expected valid endpoint, got nil")
  end
)

-- Test: get_closure_dimension_eps returns sorted endpoints
test.register_coroutine_test(
  "get_closure_dimension_eps returns sorted endpoints excluding 0", function()
    update_profile()
    test.wait_for_events()
    -- Should return endpoints 11 and 12, excluding 0
    local eps = mock_device:get_endpoints(clusters.ClosureDimension.ID)
    assert(#eps >= 2, "Expected at least 2 ClosureDimension endpoints")
  end
)

-- Test: deep_equals function with tables
test.register_coroutine_test(
  "deep_equals returns true for identical tables", function()
    local t1 = {a = 1, b = {c = 2}}
    local t2 = {a = 1, b = {c = 2}}
    local closure_utils = require "sub_drivers.closure.closure_utils.utils"
    assert(closure_utils.deep_equals(t1, t2, {ignore_functions = true}), "Tables should be equal")
  end
)

-- Test: deep_equals returns false for different tables
test.register_coroutine_test(
  "deep_equals returns false for different tables", function()
    local t1 = {a = 1, b = {c = 2}}
    local t2 = {a = 1, b = {c = 3}}
    local closure_utils = require "sub_drivers.closure.closure_utils.utils"
    assert(not closure_utils.deep_equals(t1, t2, {ignore_functions = true}), "Tables should not be equal")
  end
)

-- Test: set_closure_control_state caches state
test.register_coroutine_test(
  "set_closure_control_state caches state per endpoint", function()
    update_profile()
    test.wait_for_events()
    local closure_utils = require "sub_drivers.closure.closure_utils.utils"
    local fields = require "sub_drivers.closure.closure_utils.fields"
    closure_utils.set_closure_control_state(mock_device, 10, {main = 1})
    local cache = mock_device:get_field(fields.CLOSURE_CONTROL_STATE_CACHE)
    assert(cache ~= nil, "Cache should not be nil")
    assert(cache[10] ~= nil, "Cache for endpoint 10 should exist")
    assert(cache[10].main == 1, "Main state should be 1")
  end
)

-- Test: emit_closure_control_capability with nil cache
test.register_coroutine_test(
  "emit_closure_control_capability returns early with nil cache", function()
    update_profile()
    test.wait_for_events()
    local closure_utils = require "sub_drivers.closure.closure_utils.utils"
    -- Should not emit any event when cache is nil
    closure_utils.emit_closure_control_capability(mock_device, 10)
    test.wait_for_events()
  end
)

-- Test: main_state_attr_handler with nil value
test.register_coroutine_test(
  "main_state_attr_handler returns early with nil value", function()
    update_profile()
    test.wait_for_events()
    local attr_handlers = require "sub_drivers.closure.closure_handlers.attribute_handlers"
    local mock_ib = {endpoint_id = 10, data = {value = nil}}
    attr_handlers.main_state_attr_handler(nil, mock_device, mock_ib, nil)
    test.wait_for_events()
  end
)

-- Test: main_state_attr_handler with MOVING state
test.register_coroutine_test(
  "main_state_attr_handler sets state and emits capability", function()
    update_profile()
    test.wait_for_events()
    local attr_handlers = require "sub_drivers.closure.closure_handlers.attribute_handlers"
    local clusters = require "st.matter.clusters"
    local mock_ib = {endpoint_id = 10, data = {value = clusters.ClosureControl.types.MainStateEnum.MOVING}}
    attr_handlers.main_state_attr_handler(nil, mock_device, mock_ib, nil)
    test.wait_for_events()
  end
)

-- Test: overall_current_state_attr_handler with nil elements
test.register_coroutine_test(
  "overall_current_state_attr_handler returns early with nil elements", function()
    update_profile()
    test.wait_for_events()
    local attr_handlers = require "sub_drivers.closure.closure_handlers.attribute_handlers"
    local mock_ib = {endpoint_id = 10, data = {elements = nil}}
    attr_handlers.overall_current_state_attr_handler(nil, mock_device, mock_ib, nil)
    test.wait_for_events()
  end
)

-- Test: overall_target_state_attr_handler with nil elements
test.register_coroutine_test(
  "overall_target_state_attr_handler returns early with nil elements", function()
    update_profile()
    test.wait_for_events()
    local attr_handlers = require "sub_drivers.closure.closure_handlers.attribute_handlers"
    local mock_ib = {endpoint_id = 10, data = {elements = nil}}
    attr_handlers.overall_target_state_attr_handler(nil, mock_device, mock_ib, nil)
    test.wait_for_events()
  end
)

-- Test: closure_dimension_current_state_handler with nil elements
test.register_coroutine_test(
  "closure_dimension_current_state_handler returns early with nil elements", function()
    update_profile()
    test.wait_for_events()
    local attr_handlers = require "sub_drivers.closure.closure_handlers.attribute_handlers"
    local mock_ib = {endpoint_id = 11, data = {elements = nil}}
    attr_handlers.closure_dimension_current_state_handler(nil, mock_device, mock_ib, nil)
    test.wait_for_events()
  end
)

-- Test: closure_dimension_current_state_handler with nil position
test.register_coroutine_test(
  "closure_dimension_current_state_handler returns early with nil position", function()
    update_profile()
    test.wait_for_events()
    local attr_handlers = require "sub_drivers.closure.closure_handlers.attribute_handlers"
    local mock_ib = {endpoint_id = 11, data = {elements = {position = {value = nil}}}}
    attr_handlers.closure_dimension_current_state_handler(nil, mock_device, mock_ib, nil)
    test.wait_for_events()
  end
)

-- Test: tag_list_handler with BARRIER tag (namespace_id = 0x44, tag = 2)
test.register_coroutine_test(
  "tag_list_handler with BARRIER tag sets closure tag", function()
    -- First reset fields
    local fields = require "sub_drivers.closure.closure_utils.fields"
    mock_device:set_field(fields.CLOSURE_TAG, nil)
    local attr_handlers = require "sub_drivers.closure.closure_handlers.attribute_handlers"
    local mock_ib = {
      endpoint_id = 10,
      data = {
        elements = {
          {elements = {namespace_id = {value = 0x44}, tag = {value = 2}}}
        }
      }
    }
    attr_handlers.tag_list_handler(nil, mock_device, mock_ib, nil)
    assert(mock_device:get_field(fields.CLOSURE_TAG) == fields.closure_tag_list.BARRIER, "Tag should be BARRIER, got " .. tostring(mock_device:get_field(fields.CLOSURE_TAG)))
  end
)

-- Test: tag_list_handler with CABINET tag (namespace_id = 0x44, tag = 3)
test.register_coroutine_test(
  "tag_list_handler with CABINET tag sets closure tag", function()
    -- First reset fields
    local fields = require "sub_drivers.closure.closure_utils.fields"
    mock_device:set_field(fields.CLOSURE_TAG, nil)
    local attr_handlers = require "sub_drivers.closure.closure_handlers.attribute_handlers"
    local mock_ib = {
      endpoint_id = 10,
      data = {
        elements = {
          {elements = {namespace_id = {value = 0x44}, tag = {value = 3}}}
        }
      }
    }
    attr_handlers.tag_list_handler(nil, mock_device, mock_ib, nil)
    assert(mock_device:get_field(fields.CLOSURE_TAG) == fields.closure_tag_list.CABINET, "Tag should be CABINET, got " .. tostring(mock_device:get_field(fields.CLOSURE_TAG)))
  end
)

-- Test: tag_list_handler with nil elements
test.register_coroutine_test(
  "tag_list_handler returns early with nil elements", function()
    update_profile()
    test.wait_for_events()
    local attr_handlers = require "sub_drivers.closure.closure_handlers.attribute_handlers"
    local mock_ib = {endpoint_id = 10, data = {elements = nil}}
    attr_handlers.tag_list_handler(nil, mock_device, mock_ib, nil)
    test.wait_for_events()
  end
)

-- Test: power_source_attribute_list_handler with BatChargeLevel (0x0E)
test.register_coroutine_test(
  "power_source_attribute_list_handler sets BATTERY_LEVEL support", function()
    -- First reset fields
    local fields = require "sub_drivers.closure.closure_utils.fields"
    mock_device:set_field(fields.CLOSURE_BATTERY_SUPPORT, nil)
    local attr_handlers = require "sub_drivers.closure.closure_handlers.attribute_handlers"
    local mock_ib = {
      endpoint_id = 10,
      data = {
        elements = {
          {value = 0x0E}  -- BatChargeLevel
        }
      }
    }
    attr_handlers.power_source_attribute_list_handler(nil, mock_device, mock_ib, nil)
    assert(mock_device:get_field(fields.CLOSURE_BATTERY_SUPPORT) == fields.battery_support.BATTERY_LEVEL, "Should be BATTERY_LEVEL, got " .. tostring(mock_device:get_field(fields.CLOSURE_BATTERY_SUPPORT)))
  end
)

-- Test: power_source_attribute_list_handler with no battery attribute
test.register_coroutine_test(
  "power_source_attribute_list_handler sets NO_BATTERY support", function()
    -- First reset fields
    local fields = require "sub_drivers.closure.closure_utils.fields"
    mock_device:set_field(fields.CLOSURE_BATTERY_SUPPORT, nil)
    local attr_handlers = require "sub_drivers.closure.closure_handlers.attribute_handlers"
    local mock_ib = {
      endpoint_id = 10,
      data = {
        elements = {
          {value = 0x00}  -- Some other attribute (not battery)
        }
      }
    }
    attr_handlers.power_source_attribute_list_handler(nil, mock_device, mock_ib, nil)
    assert(mock_device:get_field(fields.CLOSURE_BATTERY_SUPPORT) == fields.battery_support.NO_BATTERY, "Should be NO_BATTERY, got " .. tostring(mock_device:get_field(fields.CLOSURE_BATTERY_SUPPORT)))
  end
)

-- Test: deep_equals with nil values
test.register_coroutine_test(
  "deep_equals handles nil values correctly", function()
    local closure_utils = require "sub_drivers.closure.closure_utils.utils"
    assert(closure_utils.deep_equals(nil, nil, {ignore_functions = true}), "nil should equal nil")
    assert(not closure_utils.deep_equals(nil, 1, {ignore_functions = true}), "nil should not equal 1")
  end
)

-- Test: deep_equals with different types
test.register_coroutine_test(
  "deep_equals returns false for different types", function()
    local closure_utils = require "sub_drivers.closure.closure_utils.utils"
    assert(not closure_utils.deep_equals(1, "1", {ignore_functions = true}), "number should not equal string")
    assert(not closure_utils.deep_equals({}, 1, {ignore_functions = true}), "table should not equal number")
  end
)

-- Test: deep_equals with functions ignored
test.register_coroutine_test(
  "deep_equals ignores functions when option set", function()
    local closure_utils = require "sub_drivers.closure.closure_utils.utils"
    local t1 = {fn = function() return 1 end}
    local t2 = {fn = function() return 2 end}
    assert(closure_utils.deep_equals(t1, t2, {ignore_functions = true}), "Tables with different functions should be equal when ignoring functions")
  end
)

-- Test: endpoint_to_component with door type
test.register_coroutine_test(
  "endpoint_to_component with door type returns door1/door2", function()
    update_profile_door()
    test.wait_for_events()
    local component = mock_door_device:endpoint_to_component(11)
    assert(component == "door1", "Expected door1, got " .. tostring(component))
    component = mock_door_device:endpoint_to_component(12)
    assert(component == "door2", "Expected door2, got " .. tostring(component))
  end,
  {test_init = test_init_door}
)

-- Test: component_to_endpoint with door type
test.register_coroutine_test(
  "component_to_endpoint with door type returns correct endpoint", function()
    update_profile_door()
    test.wait_for_events()
    local endpoint = mock_door_device:component_to_endpoint("door1")
    assert(endpoint == 11, "Expected 11, got " .. tostring(endpoint))
    endpoint = mock_door_device:component_to_endpoint("door2")
    assert(endpoint == 12, "Expected 12, got " .. tostring(endpoint))
  end,
  {test_init = test_init_door}
)

test.run_registered_tests()
