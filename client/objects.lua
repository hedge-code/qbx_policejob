local sharedConfig = require 'config.shared'

local function getClosestObject(objects, position, maxDistance, isFixed)
    local minDistance, currentIndex
    if #objects == 0 then return end

    for i = 1, #objects do
        local coords
        if isFixed then
            coords = GlobalState.fixedCoords[objects[i]]
        else
            local object = NetworkGetEntityFromNetworkId(objects[i])
            coords = GetEntityCoords(object).xyz
        end

        local distance = #(position - coords)
        if distance < maxDistance then
            if not minDistance or distance < minDistance then
                minDistance = distance
                currentIndex = i
            end
        end
    end

    return currentIndex
end

---Spawn police object.
---@param item string name from `config/shared.lua`
RegisterNetEvent('police:client:spawnPObj', function(item)
    if QBX.PlayerData.job.type ~= 'leo' or not QBX.PlayerData.job.onduty then return end

    if cache.vehicle then return exports.qbx_core:Notify(locale('error.in_vehicle'), 'error') end

    if lib.progressBar({
        duration = 2500,
        label = locale('progressbar.place_object'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true,
            mouse = false
        },
        anim = {
            dict = 'anim@narcotics@trash',
            clip = 'drop_front'
        }
    }) then
        local objectConfig = sharedConfig.objects[item]
        local forward = GetEntityForwardVector(cache.ped)
        local spawnCoords = GetEntityCoords(cache.ped).xyz + forward * 0.5
        local netid, error = lib.callback.await('police:server:spawnObject', false,
                                                objectConfig.model, spawnCoords, GetEntityHeading(cache.ped))

        if not netid then return exports.qbx_core:Notify(locale(error), 'error') end

        local object = NetworkGetEntityFromNetworkId(netid)
        PlaceObjectOnGroundProperly(object)
        FreezeEntityPosition(object, objectConfig.freeze)
    else
        exports.qbx_core:Notify(locale('error.canceled'), 'error')
    end
end)

RegisterNetEvent('police:client:deleteObject', function()
    local objectId = getClosestObject(GlobalState.policeObjects, GetEntityCoords(cache.ped).xyz , 5.0)
    if not objectId then return end
    if lib.progressBar({
        duration = 2500,
        label = locale('progressbar.remove_object'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true,
            mouse = false
        },
        anim = {
            dict = 'weapons@first_person@aim_rng@generic@projectile@thermal_charge@',
            clip = 'plant_floor'
        }
    }) then
        TriggerServerEvent('police:server:despawnObject', objectId)
    else
        exports.qbx_core:Notify(locale('error.canceled'), 'error')
    end
end)

---Spawn a spike strip.
RegisterNetEvent('police:client:SpawnSpikeStrip', function()
    if QBX.PlayerData.job.type ~= 'leo' or not QBX.PlayerData.job.onduty then return end
    if #GlobalState.spikeStrips >= sharedConfig.maxSpikes then
        return exports.qbx_core:Notify(locale('error.no_spikestripe'), 'error')
    end

    if cache.vehicle then return exports.qbx_core:Notify(locale('error.in_vehicle'), 'error') end

    if lib.progressBar({
        duration = 2500,
        label = locale('progressbar.place_object'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true,
            mouse = false
        },
        anim = {
            dict = 'amb@medic@standing@kneel@enter',
            clip = 'enter'
        }
    }) then
        local spawnCoords = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, 2.0, 0)
        local netid, error = lib.callback.await('police:server:spawnSpikeStrip', false,
                                                spawnCoords, GetEntityHeading(cache.ped))

        if not netid then
            return exports.qbx_core:Notify(locale(error), 'error')
        end

        lib.requestAnimDict('p_ld_stinger_s')
        local spike = NetworkGetEntityFromNetworkId(netid)
        PlayEntityAnim(spike, 'p_stinger_s_deploy', 'p_ld_stinger_s', 1000.0, false, false, false, 0.0, 0)
        PlaceObjectOnGroundProperly(spike)
        RemoveAnimDict('p_ld_stinger_s')
    else
        exports.qbx_core:Notify(locale('error.canceled'), 'error')
    end

    RemoveAnimDict('amb@medic@standing@kneel@enter')
end)

---Check https://github.com/overextended/ox_lib/blob/master/imports/waitFor/shared.lua
---Yields the current thread until a non-nil value.
---@generic T
---@param value T?
---@param timeout? number | false Value out after `~x` ms. Defaults to 1000, unless set to `false`.
---@async
local function silentWaitFor(value, timeout)
    if value then return value end

    if timeout or timeout == nil then
        if type(timeout) ~= 'number' then timeout = 1000 end
    end

    local start = timeout and GetGameTimer()

    while value == nil do
        Wait(0)

        local elapsed = timeout and GetGameTimer() - start

        if elapsed and elapsed > timeout then
            return value
        end
    end

    return value
end

local WHEEL_NAMES = {
    'wheel_lf',
    'wheel_rf',
    'wheel_lm',
    'wheel_rm',
    'wheel_lr',
    'wheel_rr',
}

local closestSpike
CreateThread(function()
    while true do
        closestSpike = getClosestObject(GlobalState.spikeStrips, GetEntityCoords(cache.ped).xyz, 30, true)
        Wait(500)
    end
end)

local function watchInVehicle(vehicle)
    CreateThread(function ()
        local wheels = {}
        for i = 1, #WHEEL_NAMES do
            local w = GetEntityBoneIndexByName(vehicle, WHEEL_NAMES[i])
            if w ~= -1 then wheels[#wheels + 1] = { wheel = w, index = i - 1 } end
        end

        silentWaitFor(cache.value, 2000)

        while cache.vehicle do
            if closestSpike then
                for i = 1, #wheels do
                    if wheels[i].wheel then
                        local wheelPosition = GetWorldPositionOfEntityBone(cache.vehicle, wheels[i].wheel)

                        if getClosestObject(GlobalState.spikeStrips, wheelPosition, 1.8, true) then
                            local index = wheels[i].index
                            if not IsVehicleTyreBurst(cache.vehicle, index, true)
                                or IsVehicleTyreBurst(cache.vehicle, index, false)
                            then
                                SetVehicleTyreBurst(cache.vehicle, index, false, 1000.0)
                            end
                        end
                    end
                end
                Wait(0)
            else
                Wait(250)
            end
        end
    end)
end

local function watchOutOfVehicle()
    CreateThread(function ()
        silentWaitFor(not cache.value, 2000)

        while true do
            if LocalPlayer.state.isLoggedIn and QBX.PlayerData.job.type == 'leo' then
                if QBX.PlayerData.job.onduty and closestSpike then
                    if getClosestObject(GlobalState.spikeStrips, GetEntityCoords(cache.ped).xyz, 4, true) then
                        local isOpen, text = lib.isTextUIOpen()
                        if not isOpen or text ~= locale('info.delete_spike') then
                            lib.showTextUI(locale('info.delete_spike'))
                        end

                        if IsControlJustPressed(0, 38) then
                            if lib.progressBar({
                                duration = 2500,
                                label = locale('progressbar.remove_object'),
                                useWhileDead = false,
                                canCancel = true,
                                disable = {
                                    car = true,
                                    move = true,
                                    combat = true,
                                    mouse = false
                                },
                                anim = {
                                    dict = 'weapons@first_person@aim_rng@generic@projectile@thermal_charge@',
                                    clip = 'plant_floor'
                                }
                            }) then
                                TriggerServerEvent('police:server:despawnSpikeStrip', closestSpike)
                                lib.hideTextUI()
                            else
                                exports.qbx_core:Notify(locale('error.canceled'), 'error')
                            end
                        end
                    else
                        lib.hideTextUI()
                    end
                    Wait(0)
                else
                    Wait(500)
                end
            else
                Wait(5000)
            end

            if cache.vehicle then
                return lib.hideTextUI()
            end
        end
    end)
end

lib.onCache('vehicle', function(vehicle)
    if vehicle then
        watchInVehicle(vehicle)
    else
        watchOutOfVehicle()
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if cache.vehicle then
        watchInVehicle(cache.vehicle)
    else
        watchOutOfVehicle()
    end
end)

AddEventHandler('onResourceStop', function (resource)
    if resource ~= GetCurrentResourceName() then return end
    local isOpen, text = lib.isTextUIOpen()
    if isOpen and text == locale('info.delete_spike') then
        lib.hideTextUI()
    end
end)
