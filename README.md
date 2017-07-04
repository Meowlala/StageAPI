# StageAPI
API for adding new stages to The Binding of Isaac: Afterbirth+ without replacing old ones, built off of Sentinel's original API.

Creating a stage is relatively simple! But, before starting, you'll need to generate the necessary room lua files.

For that you'll need to download [STBProcessor](https://github.com/Meowlala/STBProcessor), then uzip it and drag your room stb file over the `convertstb.bat` file, then take output.lua and rename it as you like.

With that done, you can begin programming your mod. You'll want to start something like this:

    local function fnName()               -- This function will be called when the StageAPI loads
        -- do StageAPI things
    end

    local START_FUNC = fnName             -- Defines the function that will be called when StageAPI loads

    if StageAPI then START_FUNC()         -- Blob that, assuming the above code was implemented correctly, will ensure that your function is called when StageAPI loads.
    else if not __stageAPIInit then
        __stageAPIInit = {}
    end __stageAPIInit[#__stageAPIInit + 1] = START_FUNC
    end

That code will call the function fnName when StageAPI loads. Inside the function you can start setting up your floor!

    local rooms = require("rooms.lua")
    local bossrooms = require("bossrooms.lua") -- This will be the file obtained from using STBProcessor
    
    local isMultiStage = false -- Can also pass false / true directly into GetStageConfig, this is just for show
    
    local stage = StageAPI.GetStageConfig("MyNewFloor", rooms, bossrooms, isMultiStage)
 
Now you have a stage that is techinically playable! You'll want to read the docs to figure out how to use backdrops and change the sheets of grid entities. You can use the command `cstage MyNewFloor` to access your stage for testing purposes.
