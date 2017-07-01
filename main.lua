--[[
    To ensure StageAPI is loaded when using your mod, code similar to this should be included in your mod:

    local function fnName()               -- This function will be called when the StageAPI loads
        -- do StageAPI things
    end

    local START_FUNC = fnName             -- Defines the function that will be called when StageAPI loads

    if StageAPI then START_FUNC()         -- Blob that, assuming the above code was implemented correctly, will ensure that your function is called when StageAPI loads.
    else if not __stageAPIInit then
        __stageAPIInit = {}
    end __stageAPIInit[#__stageAPIInit + 1] = START_FUNC
    end

    -- EXAMPLE END --
]]

local function start()
    local StageSystemVer = 2.0
    if not StageAPI or StageSystemVer > StageAPI.Version then require "stageapi" end

    -- Call the "start" function of
    -- mods that loaded before this API
    if __stageAPIInit then
    	for _, fn in pairs(__stageAPIInit) do
    		fn()
    	end
    	__stageAPIInit = {}
    end
end

-- API START FUNCTION
local START_FUNC = start

if AlphaAPI then START_FUNC()
else if not __alphaInit then
    __alphaInit = {}
end __alphaInit[#__alphaInit + 1] = START_FUNC
end
