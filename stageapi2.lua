-- INITIALIZATION VARIABLES START --
StageAPI = {
    Version = 3.0,
    Overlays = {},
    CurrentStage = nil,
    NextStage = nil,
    NextNextStage = nil,
    InitializingStage = nil,
    RoomsCleared = {}
}

local mod = RegisterMod("Stage API", 1)
local api_mod = AlphaAPI.registerMod(mod)
local json = require("json")

-- RNG object for when we need to set seeds.
local rng = RNG()
rng:SetSeed(Random(), 1)

local function random(min, max) -- Re-implements random()
    if min ~= nil and max ~= nil then -- Min and max passed, integer [min,max]
        return math.floor(rng:RandomFloat() * (max - min + 1) + min)
    elseif min ~= nil then -- Only min passed, integer [0, min]
        return random(1, min) -- math.floor(rng:RandomFloat() * (min + 1))
    end
    return rng:RandomFloat() -- float [0,1]
end

local VECTOR_ZERO = Vector(0, 0)

local bridgeType = Isaac.GetEntityTypeByName("StageAPIBridge")
local bridgeVariant = Isaac.GetEntityVariantByName("StageAPIBridge")

local function VectorToGrid(x,y)
    local width = AlphaAPI.GAME_STATE.ROOM:GetGridWidth()
    return width + 1 + (x + width * y)
end

local function IndexTo2DGrid(index)
    local width = AlphaAPI.GAME_STATE.ROOM:GetGridWidth()
    local height = AlphaAPI.GAME_STATE.ROOM:GetGridHeight()
    return index % width, index % height
end

local CorrectedGridTypes = {
    [1000]=GridEntityType.GRID_ROCK,
    [1001]=GridEntityType.GRID_ROCK_BOMB,
    [1002]=GridEntityType.GRID_ROCK_ALT,
    [1300]=GridEntityType.GRID_TNT,
    [1497]=GridEntityType.GRID_POOP,
    [1496]=GridEntityType.GRID_POOP,
    [1495]=GridEntityType.GRID_POOP,
    [1494]=GridEntityType.GRID_POOP,
    [1490]=GridEntityType.GRID_POOP,
    [1500]=GridEntityType.GRID_POOP,
    [1900]=GridEntityType.GRID_ROCKB,
    [1930]=GridEntityType.GRID_SPIKES,
    [1931]=GridEntityType.GRID_SPIKES_ONOFF,
    [1940]=GridEntityType.GRID_SPIDERWEB,
    [3000]=GridEntityType.GRID_PIT,
    [4000]=GridEntityType.GRID_LOCK,
    [4500]=GridEntityType.GRID_PRESSURE_PLATE,
    [9000]=GridEntityType.GRID_TRAPDOOR,
    [9100]=GridEntityType.GRID_STAIRS,
    [10000]=GridEntityType.GRID_GRAVITY
}

local game   = AlphaAPI.GAME_STATE.GAME
local level  = AlphaAPI.GAME_STATE.LEVEL
local room   = AlphaAPI.GAME_STATE.ROOM
local players = AlphaAPI.GAME_STATE.PLAYERS
-- INITIALIZATION VARIABLES END --

-- STAGEAPI CLASSES
do
    local SpriteConfig = {}
    function SpriteConfig:_init(anm2, sheetVariants, animation, respectOldSpriteFrame, respectOldSpriteAnimation, oldSpriteAnimationsMap, playRandom)
        self.SPRITE = Sprite()
        self.SPRITE:Load(anm2)
        self.SHEETVARIANTS = sheetVariants
        self.ANIMATION = animation
        self.RESPECTFRAME = respectOldSpriteFrame
        self.RESPECTANIM = respectOldSpriteAnimation
        self.ANIMMAP = oldSpriteAnimationsMap
        self.PLAYRANDOM = playRandom
    end

    function SpriteConfig:GetSprite(variantSeed, animSeed, oldSprite, useFinished, sprite, animation, respectOldSpriteFrame, respectOldSpriteAnimation, oldSpriteAnimationsMap, playRandom)
        variantSeed = variantSeed or AlphaAPI.GAME_STATE.ROOM:GetDecorationSeed()
        animSeed = animSeed or Isaac.GetTime()
        animation = animation or self.ANIMATION
        sprite = sprite or self.SPRITE
        respectOldSpriteFrame = respectOldSpriteFrame or self.RESPECTFRAME
        respectOldSpriteAnimation = respectOldSpriteAnimation or self.RESPECTANIM
        oldSpriteAnimationsMap = oldSpriteAnimationsMap or self.ANIMMAP
        playRandom = playRandom or self.PLAYRANDOM

        if self.SHEETVARIANTS then
            if type(self.SHEETVARIANTS) == "table" then
                rng:SetSeed(variantSeed, 0)
                local variant = self.SHEETVARIANTS[random(1, #self.SHEETVARIANTS)]
                if type(variant) == "table" then
                    for num, sheet in ipairs(variant) do
                        sprite:ReplaceSpritesheet(num, sheet)
                    end
                else
                    sprite:ReplaceSpritesheet(0, variant)
                end
            else
                sprite:ReplaceSpritesheet(0, self.SHEETVARIANTS)
            end
        end

        if animation then
            sprite:Play(animation, true)
        end

        if playRandom then
            sprite:PlayRandom(animSeed)
        end

        if oldSprite then
            if respectOldSpriteFrame and animation then
                sprite:SetFrame(animation, oldSprite:GetFrame())
            end

            if respectOldSpriteAnimation and oldSpriteAnimationsMap then
                local shouldPlay
                for oldSpriteAnim, newSpriteAnim in pairs(oldSpriteAnimationsMap) do
                    local checkAgainst = oldSpriteAnim
                    local play         = newSpriteAnim
                    if type(oldSpriteAnim) ~= "string" then
                        checkAgainst = newSpriteAnim
                    end

                    if useFinished then
                        if oldSprite:IsPlaying(checkAgainst) or oldSprite:IsFinished(checkAgainst) then
                            shouldPlay = play
                        end
                    else
                        if oldSprite:IsPlaying(checkAgainst) then
                            shouldPlay = play
                        end
                    end
                end

                if shouldPlay then
                    sprite:Play(shouldPlay, true)
                    if respectOldSpriteFrame then
                        sprite:SetFrame(shouldPlay, oldSprite:GetFrame())
                    end
                end
            end
        end

        sprite:LoadGraphics()
        return sprite
    end

    function StageAPI.GetSpriteConfig(anm2, sheetVariants, animation, respectOldSpriteFrame, respectOldSpriteAnimation, oldSpriteAnimationsMap, playRandom)
        local inst = {}
        setmetatable(inst, {__index = SpriteConfig})
        inst:_init(anm2, sheetVariants, animation, respectOldSpriteFrame, respectOldSpriteAnimation, oldSpriteAnimationsMap, playRandom)
        return inst
    end

    local GridConfig = {}
    function GridConfig:_init()
        if StageAPI.DefaultGridConfig then
            self.ROCKSPRITE = StageAPI.DefaultGridConfig.ROCKSPRITE
            self.PITSPRITE = StageAPI.DefaultGridConfig.PITSPRITE
            self.DOORSPRITE = StageAPI.DefaultGridConfig.DOORSPRITE
            self.SECRETDOORSPRITE = StageAPI.DefaultGridConfig.SECRETDOORSPRITE
            self.DECORATIONSPRITE = StageAPI.DefaultGridConfig.DECORATIONSPRITE
            self.BRIDGESHEET = StageAPI.DefaultGridConfig.BRIDGESHEET
            self.BRIDGEFILE = StageAPI.DefaultGridConfig.BRIDGEFILE
            self.BRIDGEANIM = StageAPI.DefaultGridConfig.BRIDGEANIM
            self.ROCKREPLACECHANCES = StageAPI.DefaultGridConfig.ROCKREPLACECHANCES
        end
    end

    function GridConfig:SetRocks(sheetVariants, anm2, animationMap)
        self.ROCKSPRITE = StageAPI.GetSpriteConfig(anm2 or StageAPI.SpriteFile.Rock, sheetVariants, nil, true, true, animationMap or StageAPI.RockAnimationMap)
        Isaac.DebugString(type(self.ROCKSPRITE))
    end

    function GridConfig:SetPits(sheetVariants, anm2, animation)
        self.PITSPRITE = StageAPI.GetSpriteConfig(anm2 or StageAPI.SpriteFile.Pit, sheetVariants, animation or StageAPI.SpriteAnimations.Pit, true)
    end

    function GridConfig:SetDoors(sheetVariants, anm2, animationMap)
        self.DOORSPRITE = StageAPI.GetSpriteConfig(anm2 or StageAPI.SpriteFile.Door, sheetVariants, nil, true, true, animationMap or StageAPI.DoorAnimationMap)
    end

    function GridConfig:SetSecretDoors(sheetVariants, anm2, animationMap)
        self.SECRETDOORSPRITE = StageAPI.GetSpriteConfig(anm2 or StageAPI.SpriteFile.SecretDoor, sheetVariants, nil, true, true, animationMap or StageAPI.SecretDoorAnimationMap)
    end

    function GridConfig:SetDecoration(sheetVariants, anm2)
        self.DECORATIONSPRITE = StageAPI.GetSpriteConfig(anm2 or StageAPI.SpriteFile.Decoration, sheetVariants, nil, nil, nil, nil, true)
    end

    function GridConfig:SetBridges(sheet, anm2, animation)
        self.BRIDGESHEET = sheet
        self.BRIDGEFILE  = anm2 or StageAPI.SpriteFile.Bridge
        self.BRIDGEANIM  = animation or StageAPI.SpriteAnimations.Bridge
    end

    function GridConfig:AddRockReplaceChance(spawned, chance, replaced, replaceAll)
        if not self.ROCKREPLACECHANCES then
            self.ROCKREPLACECHANCES = {}
        end

        self.ROCKREPLACECHANCES[#self.ROCKREPLACECHANCES + 1] = {
            SPAWN = spawned,
            CHANCE = chance,
            REPLACE = replaced or GridEntityType.GRID_ROCK,
            REPLACEALL = replaceAll
        }
    end

    function StageAPI.GetGridConfig()
        local inst = {}
        setmetatable(inst, {__index = GridConfig})
        inst:_init()
        return inst
    end

    local ExtraSpriteConfig = {}
    function ExtraSpriteConfig:_init()
        if StageAPI.DefaultExtraSpriteConfig then
            self.TRANSITIONSPRITE = StageAPI.DefaultExtraSpriteConfig.TRANSITIONSPRITE
            self.BOSSSPRITE = StageAPI.DefaultExtraSpriteConfig.BOSSSPRITE
            self.NAME1 = StageAPI.DefaultExtraSpriteConfig.NAME1
            self.NAME2 = StageAPI.DefaultExtraSpriteConfig.NAME2
            self.NAMESPRITE = StageAPI.DefaultExtraSpriteConfig.NAMESPRITE
            self.TRANSITIONANIM = StageAPI.DefaultExtraSpriteConfig.TRANSITIONANIM
            self.BOSSANIM = StageAPI.DefaultExtraSpriteConfig.BOSSANIM
            self.NAMEANIM = StageAPI.DefaultExtraSpriteConfig.NAMEANIM
        end
    end

    function ExtraSpriteConfig:SetTransition(icon, nearBackground, farBackground, anm2, anim)
        local sprite = Sprite()
        sprite:Load(anm2 or StageAPI.SpriteFile.Transition, true)

        if icon then
            sprite:ReplaceSpritesheet(2, icon)
        end

        if nearBackground then
            sprite:ReplaceSpritesheet(0, nearBackground)
        end

        if farBackground then
            sprite:ReplaceSpritesheet(4, farBackground)
        end

        sprite:LoadGraphics()
        self.TRANSITIONANIM = anim or StageAPI.SpriteAnimations.Transition
        self.TRANSITIONSPRITE = sprite
    end

    function ExtraSpriteConfig:SetBossAnimation(anm2, anim)
        local sprite = Sprite()
        sprite:Load(anm2 or StageAPI.SpriteFile.Boss, true)

        if spot then
            sprite:ReplaceSpritesheet(2, spot)
        end

        sprite:LoadGraphics()
        self.BOSSANIM = anim or StageAPI.SpriteAnimations.Boss
        self.BOSSSPRITE = sprite
    end

    function ExtraSpriteConfig:SetNameSprite(name1, name2, anm2, anim)
        local sprite = Sprite()
        sprite:Load(anm2 or StageAPI.SpriteFile.Namestreak, true)

        self.NAMEANIM = anim or StageAPI.SpriteAnimations.Namestreak
        self.NAME1 = name1
        self.NAME2 = name2
        self.NAMESPRITE = sprite
    end

    function StageAPI.GetExtraSpriteConfig()
        local inst = {}
        setmetatable(inst, {__index = ExtraSpriteConfig})
        inst:_init()
        return inst
    end

    local BossConfig = {}
    function BossConfig:_init()
        self.BOSSES = {}
    end

    function BossConfig:AddBoss(bossType, portrait, name, spot, bossVariant, bossSubType, priority)
        self.BOSSES[#self.BOSSES + 1] = {
            TYPE = bossType,
            PORTRAIT = portrait,
            NAME = name,
            SPOT = spot,
            VARIANT = bossVariant,
            SUBTYPE = bossSubType,
            PRIORITY = priority
        }
    end

    function StageAPI.GetBossConfig()
        local inst = {}
        setmetatable(inst, {__index = BossConfig})
        inst:_init()
        return inst
    end

    local BackdropVariant = {}
    function BackdropVariant:_init()
        self.NFLOORS = {}
        self.LFLOORS = {}
        self.CORNERS = {}
        self.WALLS = {}
    end

    function BackdropVariant:AddNFloors(nfloors)
        if type(nfloors) == "table" then
            for _, nfloor in ipairs(nfloors) do
                self.NFLOORS[#self.NFLOORS + 1] = nfloor
            end
        else
            self.NFLOORS[#self.NFLOORS + 1] = nfloors
        end
    end

    function BackdropVariant:AddLFloors(lfloors)
        if type(lfloors) == "table" then
            for _, lfloor in ipairs(lfloors) do
                self.LFLOORS[#self.LFLOORS + 1] = lfloor
            end
        else
            self.LFLOORS[#self.LFLOORS + 1] = lfloors
        end
    end

    function BackdropVariant:AddCorners(corners)
        if type(corners) == "table" then
            for _, corner in ipairs(corners) do
                self.CORNERS[#self.CORNERS + 1] = corner
            end
        else
            self.CORNERS[#self.CORNERS + 1] = corners
        end
    end

    function BackdropVariant:AddWalls(walls)
        if type(walls) == "table" then
            for _, wall in ipairs(walls) do
                self.WALLS[#self.WALLS + 1] = wall
            end
        else
            self.WALLS[#self.WALLS + 1] = walls
        end
    end

    function StageAPI.GetBackdropVariant()
        local inst = {}
        setmetatable(inst, {__index = BackdropVariant})
        inst:_init()
        return inst
    end

    local BackdropConfig = {}
    function BackdropConfig:_init(anm2)
        self.ANM2 = anm2 or StageAPI.SpriteFile.Backdrop
        self.DATA = {}
    end

    function BackdropConfig:AddBackdropVariant(backdropVariant, roomType)
        roomType = roomType or "Default"
        if not self.DATA[roomType] then
            self.DATA[roomType] = {}
        end

        self.DATA[roomType][#self.DATA[roomType] + 1] = backdropVariant
    end

    function StageAPI.GetBackdropConfig(anm2)
        local inst = {}
        setmetatable(inst, {__index = BackdropConfig})
        inst:_init(anm2)
        return inst
    end

    local Overlay = {}
    function Overlay:_init(anm2, velocity, offset, position)
        local sprite = Sprite()
        sprite:Load(anm2, true)
        sprite:Play("Idle")

        self.Sprite = sprite
        self.Position = position or VECTOR_ZERO
        self.Offset = offset or VECTOR_ZERO
        self.Velocity = velocity or VECTOR_ZERO
    end

    local updateTick = false
    function Overlay:Render()
        if updateTick then self.Sprite:Update() end
        updateTick = not updateTick
        local overlayoffset = VECTOR_ZERO
        self.Position = self.Position + self.Velocity
        overlayoffset = self.Position
        if overlayoffset.X < 0 then self.Position = Vector(overlayoffset.X+512, overlayoffset.Y) end
        if overlayoffset.Y < 0 then self.Position = Vector(overlayoffset.X, overlayoffset.Y+512) end
        if overlayoffset.X > 512 then self.Position = Vector(overlayoffset.X-512, overlayoffset.Y) end
        if overlayoffset.Y > 512 then self.Position = Vector(overlayoffset.X, overlayoffset.Y-512) end
        overlay.Sprite:Render(self.Position + overlay.Offset, VECTOR_ZERO, VECTOR_ZERO)
    end

    function StageAPI.AddOverlay(anm2, velocity, offset, position)
    	if TypeError("AddOverlay", 1, "string", anm2) then
    		local overlay = {}
            setmetatable(overlay, {__index = Overlay})
            overlay:_init(anm2, velocity, offset, position)
            StageAPI.Overlays[#StageAPI.Overlays + 1] = overlay
            return overlay
    	end
    end

    local MusicConfig = {}
    function MusicConfig:_init()
        self.MUSIC = {
            Boss = {},
            UnclearedRoom = {}
        }
    end

    function MusicConfig:AddMusic(id, roomType)
        roomType = roomType or "Default"
        if not self.MUSIC[roomType] then self.MUSIC[roomType] = {} end
        self.MUSIC[roomType][#self.MUSIC[roomType] + 1] = id
    end

    function MusicConfig:AddBossMusic(id)
        self.MUSIC.Boss[#self.MUSIC.Boss + 1] = id
    end

    function MusicConfig:AddUnclearedRoomMusic(id)
        self.MUSIC.UnclearedRoom[#self.MUSIC.UnclearedRoom + 1] = id
    end

    function StageAPI.GetMusicConfig()
        local inst = {}
        setmetatable(inst, {__index = MusicConfig})
        inst:_init()
        return inst
    end

    local StageConfig = {}
    function StageConfig:_init(name, rooms, bossRooms, isMultiStage, replaces)
        self.NAME = name
        self.ROOMS = rooms
        self.BOSSROOMS = bossRooms
        self.ISMULTISTAGE = isMultiStage
        self.REPLACES = replaces
    end

    function StageConfig:SetGridConfig(gridConfig)
        self.GRIDCONFIG = gridConfig
    end

    function StageConfig:SetExtraSpriteConfig(extraSpriteConfig)
        self.EXTRASPRITECONFIG = extraSpriteConfig
    end

    function StageConfig:SetBossConfig(bossConfig)
        self.BOSSCONFIG = bossConfig
    end

    function StageConfig:SetBackdropConfig(backdropConfig)
        self.BACKDROPCONFIG = backdropConfig
    end

    function StageConfig:SetMusicConfig(musicConfig)
        self.MUSICCONFIG = musicConfig
    end

    function StageConfig:SetBossSpot(bossSpot)
        self.BOSSSPOT = bossSpot
    end

    function StageConfig:IsInStage()
        return self.NAME == StageAPI.CurrentStage.NAME
    end

    function StageConfig:MoveToStage(floor)
        if not floor then
            if self.ISMULTISTAGE then floor = 1 else floor = 2 end
        end

        for _, Player in pairs(player) do
            Player.ControlsEnabled = false
        end

        if floor == 1 then
            StageAPI.InitializingStage = self
            StageAPI.NextStage = self
        else
            StageAPI.InitializingStage = self
        end

        Isaac.ExecuteCommand(self.REPLACES.COMMAND[floor])
        StageAPI.PlayTransitionAnimation(extraSpriteConfig)
    end

    function StageAPI.GetStageConfig(name, rooms, bossRooms, isMultiStage, replaces)
        local inst = {}
        setmetatable(inst, {__index = StageConfig})
        inst:_init(name, rooms, bossRooms, isMultiStage, replaces)
        return inst
    end
end

-- STAGEAPI ENUMS
do
    StageAPI.SpriteFile = {
        Rock = "gfx/grid/grid_rock.anm2",
        Pit = "gfx/grid/grid_pit.anm2",
        Bridge = "stageapi/bridge.anm2",
        Decoration = "gfx/grid/props_03_caves.anm2",
        Door = "gfx/grid/door_01_normaldoor.anm2",
        SecretDoor = "gfx/grid/door_08_holeinwall.anm2",
        Transition = "stageapi/customnightmare.anm2",
        Namestreak = "gfx/ui/ui_streak.anm2",
        Boss = "stageapi/customversusscreen.anm2",
        Backdrop = "stageapi/Backdrop.anm2"
    }

    StageAPI.SpriteAnimations = {
        Pit = "pit",
        Bridge = "Idle",
        Transition = "Scene",
        Boss = "Scene",
        Namestreak = "Text"
    }

    StageAPI.RockAnimationMap = {
        "normal",
        "black",
        "tinted",
        "alt",
        "bombrock",
        "big",
        "superspecial",
        "ss_broken"
    }

    StageAPI.DoorAnimationMap = {
        "Opened",
        "Closed",
        "Open",
        "Close",
        "Break",
        "KeyOpen",
        "KeyClose",
        "BrokenOpen",
        "KeyClosed",
        "GoldenKeyOpen"
    }

    StageAPI.SecretDoorAnimationMap = {
        "Open",
        "Close",
        "Hidden",
        "Opened"
    }

    StageAPI.Replace = {
        Catacombs = {
            STAGES = {LevelStage.STAGE2_1, LevelStage.STAGE2_2},
            STAGETYPES = {StageType.STAGETYPE_WOTL},
            COMMAND = {"stage 3a", "stage 4a"},
            ID = "Catacombs"
        },
        Utero = {
            STAGES = {LevelStage.STAGE4_1, LevelStage.STAGE4_2},
            STAGETYPES = {StageType.STAGETYPE_WOTL},
            COMMAND = {"stage 7a", "stage 8a"},
            ID = "Utero"
        }
    }

    Isaac.DebugString("Function setup complete")
    StageAPI.DefaultGridConfig = StageAPI.GetGridConfig()
    StageAPI.DefaultGridConfig:SetRocks("gfx/grid/rocks_catacombs.png")
    StageAPI.DefaultGridConfig:SetPits("gfx/grid/grid_pit_catacombs.png")
    StageAPI.DefaultGridConfig:SetDoors("gfx/grid/door_01_normaldoor.png")
    StageAPI.DefaultGridConfig:SetSecretDoors("gfx/grid/door_08_holeinwall_caves.png")
    StageAPI.DefaultGridConfig:SetDecoration("gfx/grid/props_03_caves.png")
    StageAPI.DefaultGridConfig:SetBridges("gfx/grid/grid_bridge_catacombs.png")
    StageAPI.DefaultGridConfig:AddRockReplaceChance(GridEntityType.GRID_ROCKT, 32)
    StageAPI.DefaultGridConfig:AddRockReplaceChance(GridEntityType.GRID_ROCK_BOMB, 32)
    StageAPI.DefaultGridConfig:AddRockReplaceChance(GridEntityType.GRID_ROCK_SS, 48)

    StageAPI.DefaultExtraSpriteConfig = StageAPI.GetExtraSpriteConfig()
    StageAPI.DefaultExtraSpriteConfig:SetBossAnimation()
    StageAPI.DefaultExtraSpriteConfig:SetTransition("stageapi/LevelIcon.png")
    StageAPI.DefaultExtraSpriteConfig:SetNameSprite("stageapi/effect_catacombs1_streak.png", "stageapi/effect_catacombs2_streak.png")

    local BossList = {
        {EntityType.ENTITY_GURGLING, "turdlings", 2},
        {EntityType.ENTITY_PIN, "thefrail", 2},
        {EntityType.ENTITY_RAG_MEGA, "ragmega"},
        {EntityType.ENTITY_DINGLE, "dangle", 1},
        {EntityType.ENTITY_BIG_HORN, "bighorn"},
        {EntityType.ENTITY_RAG_MAN, "405.0_ragman", 0},
        {EntityType.ENTITY_LITTLE_HORN, "404.0_littlehorn"},
        {EntityType.ENTITY_FORSAKEN, "403.0_theforsaken"},
        {EntityType.ENTITY_STAIN, "401.0_thestain"},
        {EntityType.ENTITY_GURGLING, "276.0_gurglings", 1},
        {EntityType.ENTITY_POLYCEPHALUS, "269.0_polycephalus"},
        {EntityType.ENTITY_DARK_ONE, "267.0_darkone"},
        {EntityType.ENTITY_MEGA_FATTY, "264.0_megafatty"},
        {EntityType.ENTITY_DINGLE, "261.0_dingle", 0},
        {EntityType.ENTITY_WIDOW, "100.1_thewretched", 1},
        {EntityType.ENTITY_WIDOW, "100.0_widow", 0},
        {EntityType.ENTITY_GURDY_JR, "99.0_gurdyjr"},
        {EntityType.ENTITY_HEADLESS_HORSEMAN, "82.0_headlesshorseman"},
        {EntityType.ENTITY_FALLEN, "81.0_thefallen"},
        {EntityType.ENTITY_GEMINI, "79.2_blightedovum", 2},
        {EntityType.ENTITY_GEMINI, "79.0_gemini", 0},
        {EntityType.ENTITY_FISTULA_BIG, "71.0_fistula", 0},
        {EntityType.ENTITY_FISTULA_MEDIUM, "71.0_fistula", 0},
        {EntityType.ENTITY_FISTULA_SMALL, "71.0_fistula", 0},
        {EntityType.ENTITY_PEEP, "68.0_peep", 0},
        {EntityType.ENTITY_DUKE, "67.1_thehusk", 1},
        {EntityType.ENTITY_DUKE, "67.0_dukeofflies", 0},
        {EntityType.ENTITY_PESTILENCE, "64.0_pestilence"},
        {EntityType.ENTITY_PIN, "62.0_pin", 0},
        {EntityType.ENTITY_CHUB, "28.2_carrionqueen", 2},
        {EntityType.ENTITY_CHUB, "28.1_chad", 1},
        {EntityType.ENTITY_CHUB, "28.0_chub", 0},
        {EntityType.ENTITY_MONSTRO, "20.0_monstro"},
        {EntityType.ENTITY_LARRYJR, "19.1_thehollow", 1},
        {EntityType.ENTITY_LARRYJR, "19.0_larryjr", 0}
    }

    local BossConfig = StageAPI.GetBossConfig()
    for _, boss in ipairs(BossList) do
        BossConfig:AddBoss(boss[1], "gfx/ui/boss/portrait_" .. boss[2] .. ".png", "gfx/ui/boss/bossname_" .. boss[2] .. ".png", nil, boss[3], boss[4])
    end
    Isaac.DebugString("Boss setup complete")

    local CatacombsBackdrop = StageAPI.GetBackdropConfig()

    local CatacombsVariantA = StageAPI.GetBackdropVariant()
    CatacombsVariantA:AddNFloors{"stageapi/Backdrop/Catacombs/Catacombs_nfloor.png"}
    CatacombsVariantA:AddLFloors{"stageapi/Backdrop/Catacombs/Catacombs_lfloor.png"}
    CatacombsVariantA:AddCorners{"stageapi/Backdrop/Catacombs/Catacombs1_corner.png"}
    CatacombsVariantA:AddWalls{"stageapi/Backdrop/Catacombs/Catacombs1_1.png", "stageapi/Backdrop/Catacombs/Catacombs1_2.png"}

    local CatacombsVariantB = StageAPI.GetBackdropVariant()
    CatacombsVariantB:AddNFloors{"stageapi/Backdrop/Catacombs/Catacombs_nfloor.png"}
    CatacombsVariantB:AddLFloors{"stageapi/Backdrop/Catacombs/Catacombs_lfloor.png"}
    CatacombsVariantB:AddCorners{"stageapi/Backdrop/Catacombs/Catacombs2_corner.png"}
    CatacombsVariantB:AddWalls{"stageapi/Backdrop/Catacombs/Catacombs2_1.png", "stageapi/Backdrop/Catacombs/Catacombs2_2.png"}

    CatacombsBackdrop:AddBackdropVariant(CatacombsVariantA)
    CatacombsBackdrop:AddBackdropVariant(CatacombsVariantB)

    local CatacombsMusic = StageAPI.GetMusicConfig()
    CatacombsMusic:AddMusic(Music.MUSIC_CATACOMBS)

    local CatacombsRooms = require("catacombs.lua")
    local CatacombsBossRooms = require("catacombsbosses.lua")

    local Catacombs = StageAPI.GetStageConfig("Catacombs", CatacombsRooms, CatacombsBossRooms, false, StageAPI.Replace.Catacombs)
    Catacombs:SetMusicConfig(CatacombsMusic)
    Catacombs:SetBossConfig(BossConfig)
    Catacombs:SetBossSpot("gfx/ui/boss/bossspot_04_catacombs.png")
    Catacombs:SetGridConfig(StageAPI.DefaultGridConfig)
    Catacombs:SetExtraSpriteConfig(StageAPI.DefaultExtraSpriteConfig)
    Catacombs:SetBackdropConfig(CatacombsBackdrop)

    Isaac.DebugString("Catacombs setup complete")

    StageAPI.FloorsReplaced = {
        [StageAPI.Replace.Catacombs.ID] = Catacombs,
        [StageAPI.Replace.Utero.ID] = Catacombs
    }
end

-- STAGEAPI BASIC FUNCTIONS
do
    local bridgeEntities = {}
    function StageAPI.CheckBridge(gridConfig, grid)
        if grid:ToPit() and grid.State == 1 and (gridConfig.BRIDGEFILE or gridConfig.BRIDGESHEET or gridConfig.BRIDGEANIM) then
            local index = grid:GetGridIndex()
            if not bridgeEntities[index] or not bridgeEntities[index]:Exists() then
                local bridgeEffect = Isaac.Spawn(
                    bridgeType,
                    bridgeVariant,
                    0,
                    grid.Position,
                    VECTOR_ZERO,
                    nil
                )

                local effectSprite = bridgeEffect:GetSprite()
                if gridConfig.BRIDGEFILE then
                    effectSprite:Load(gridConfig.BRIDGEFILE, false)
                end

                if gridConfig.BRIDGESHEET then
                    effectSprite:ReplaceSpritesheet(0, gridConfig.BRIDGESHEET)
                end

                if gridConfig.BRIDGEANIM then
                    effectSprite:Play(gridConfig.BRIDGEANIM, true)
                end

                effectSprite:LoadGraphics()
                bridgeEffect.SpriteOffset = Vector(4, 4)
                bridgeEffect.RenderZOffset = -10000
                bridgeEntities[grid:GetGridIndex()] = bridgeEffect
            end
        end
    end

    -- Pit initialization
    do
        local function isPit(map, gridx, gridy)
            local point = map[tostring(gridx) .. tostring(gridy)]
            if point then
                return point.TYPE == GridEntityType.GRID_PIT
            end
        end

        -- Takes whether or not there is a pit in each adjacent space, returns frame to set pit sprite to.
        function StageAPI.GetPitFrame(L, R, U, D, UL, DL, UR, DR)
            -- Words were shortened to make writing code simpler.
            local F = 0 -- Sprite frame to set

            -- First bitwise frames (works for all combinations of just left up right and down)
            if L  then F = F | 1 end
            if U  then F = F | 2 end
            if R  then F = F | 4 end
            if D  then F = F | 8 end

            -- Then a bunch of other combinations
            if U and L and not UL and not R and not D then
                F = 17
            end

            if U and R and not UR and not L and not D then
                F = 18
            end

            if L and D and not DL and not U and not R then
                F = 19
            end

            if R and D and not DR and not L and not U then
                F = 20
            end

            if L and U and R and D and not UL then
                F = 21
            end

            if L and U and R and D and not UR then
                F = 22
            end

            if L and U and R and D and not DL and not DR then
                F = 24
            end

            if L and U and R and D and not UR and not UL then
                F = 23
            end

            if U and R and D and not L and not UR then
                F = 25
            end

            if L and U and D and not R and not UL then
                F = 26
            end

            if L and U and R and UL and not UR and not D then
                F = 27
            end

            if L and U and R and UR and not UL and not D then
                F = 28
            end

            if L and U and R and not D and not UR and not UL then
                F = 29
            end

            if L and R and D and DL and not U and not DR then
                F = 30
            end

            if L and R and D and DR and not U and not DL then
                F = 31
            end

            if L and R and D and not U and not DL and not DR then
                F = 32
            end

            return F
        end

        function StageAPI.InitPit(gridConfig, grid, variantSeed, grid_map, griddata)
            -- Words were shortened to make writing code simpler.
            local L = isPit(grid_map, griddata.GRIDX - 1, griddata.GRIDY) -- Left Pit
            local R = isPit(grid_map, griddata.GRIDX + 1, griddata.GRIDY) -- Right Pit
            local U = isPit(grid_map, griddata.GRIDX, griddata.GRIDY - 1) -- Up Pit
            local D = isPit(grid_map, griddata.GRIDX, griddata.GRIDY + 1) -- Down Pit
            local UL = isPit(grid_map, griddata.GRIDX - 1, griddata.GRIDY - 1) -- Up Left Pit
            local DL = isPit(grid_map, griddata.GRIDX - 1, griddata.GRIDY + 1) -- Down Left Pit
            local UR = isPit(grid_map, griddata.GRIDX + 1, griddata.GRIDY - 1) -- Up Right Pit
            local DR = isPit(grid_map, griddata.GRIDX + 1, griddata.GRIDY + 1) -- Down Right Pit
            local F = StageAPI.GetPitFrame(L, R, U, D, UL, DL, UR, DR)
            local sprite = gridConfig.PITSPRITE:GetSprite(variantSeed, grid.Desc.SpawnSeed, grid.Sprite)
            sprite:SetFrame(gridConfig.PITSPRITE.ANIMATION, F)
            grid.Sprite = sprite
            StageAPI.CheckBridge(gridConfig, grid)
        end

        local function isGridPit(x, y)
            local index = VectorToGrid(x, y)
            Isaac.DebugString(index)
            if index then
                local grid = room:GetGridEntity(index)
                if grid and grid:ToPit() then
                    return true
                end
            end
        end

        function StageAPI.ResetPits(gridConfig, variantSeed)
            for i = 0, room:GetGridSize() do
                local grid = room:GetGridEntity(i)

                if grid and grid:ToPit() then
                    local x, y = IndexTo2DGrid(grid:GetGridIndex())
                    local L = isGridPit(x - 1, y) -- Left Pit
                    local R = isGridPit(x + 1, y) -- Right Pit
                    local U = isGridPit(x, y - 1) -- Up Pit
                    local D = isGridPit(x, y + 1) -- Down Pit
                    local UL = isGridPit(x - 1, y - 1) -- Up Left Pit
                    local DL = isGridPit(x - 1, y + 1) -- Down Left Pit
                    local UR = isGridPit(x + 1, y - 1) -- Up Right Pit
                    local DR = isGridPit(x + 1, y + 1) -- Down Right Pit
                    local F = StageAPI.GetPitFrame(L, R, U, D, UL, DL, UR, DR)
                    local sprite = gridConfig.PITSPRITE:GetSprite(variantSeed, grid.Desc.SpawnSeed, grid.Sprite)
                    sprite:SetFrame(gridConfig.PITSPRITE.ANIMATION, F)
                    grid.Sprite = sprite
                    StageAPI.CheckBridge(gridConfig, grid)
                end
            end
        end
    end

    function StageAPI.ChangePit(gridConfig, grid, variantSeed)
        grid.Sprite = gridConfig.PITSPRITE:GetSprite(variantSeed, grid.Desc.SpawnSeed, grid.Sprite)
        StageAPI.CheckBridge(gridConfig, grid)
    end

    function StageAPI.ChangeRock(gridConfig, grid, variantSeed)
        Isaac.DebugString("Changing rock!")
        grid.Sprite = gridConfig.ROCKSPRITE:GetSprite(variantSeed, grid.Desc.SpawnSeed, grid.Sprite, true)
    end

    function StageAPI.ChangeDecoration(gridConfig, grid, variantSeed)
        grid.Sprite = gridConfig.DECORATIONSPRITE:GetSprite(variantSeed, grid.Desc.SpawnSeed, grid.Sprite)
    end

    function StageAPI.ChangeDoor(gridConfig, grid, variantSeed)
        Isaac.DebugString("Changing door!")
        local door = grid:ToDoor()
        local curType = door.CurrentRoomType
        local tarType = door.TargetRoomType
        if (curType == RoomType.ROOM_SECRET or tarType == RoomType.ROOM_SECRET) and gridConfig.SECRETDOORSPRITE then
            local sprite = gridConfig.SECRETDOORSPRITE:GetSprite(variantSeed, grid.Desc.SpawnSeed, grid.Sprite)
            sprite.Rotation = door.Direction * 90 - 90
            grid.Sprite = sprite
        elseif (curType == RoomType.ROOM_DEFAULT or curType == RoomType.ROOM_SACRIFICE or curType == RoomType.ROOM_MINIBOSS) and (tarType == RoomType.ROOM_DEFAULT or tarType == RoomType.ROOM_SACRIFICE or tarType == RoomType.ROOM_MINIBOSS) and gridConfig.DOORSPRITE then
            local sprite = gridConfig.DOORSPRITE:GetSprite(variantSeed, grid.Desc.SpawnSeed, grid.Sprite)
            sprite.Rotation = door.Direction * 90 - 90
            grid.Sprite = sprite
        end
    end

    function StageAPI.ChangeGridEntities(gridConfig, variantSeed)
        variantSeed = variantSeed or room:GetDecorationSeed()
        for _, grid in ipairs(AlphaAPI.entities.grid) do
            if gridConfig.PITSPRITE and grid:ToPit() then
                StageAPI.ChangePit(gridConfig, grid, variantSeed)
            elseif gridConfig.ROCKSPRITE and grid:ToRock() then
                StageAPI.ChangeRock(gridConfig, grid, variantSeed)
            elseif gridConfig.DECORATIONSPRITE and grid:ToDecoration() then
                StageAPI.ChangeDecoration(gridConfig, grid, variantSeed)
            elseif (gridConfig.DOORSPRITE or gridConfig.SECRETDOORSPRITE) and grid:ToDoor() then
                StageAPI.ChangeDoor(gridConfig, grid, variantSeed)
            end
        end
    end

    local oddFrame = false
    function StageAPI.RenderExtraSprites(extraSpriteConfig)
        if oddFrame then
            if extraSpriteConfig then
                if extraSpriteConfig.NAMESPRITE:IsPlaying(extraSpriteConfig.NAMEANIM) then
                    extraSpriteConfig.NAMESPRITE:Update()
                    extraSpriteConfig.NAMESPRITE:Render(AlphaAPI.getScreenCenterPosition()+Vector(0,-80), VECTOR_ZERO, VECTOR_ZERO)
                end

                if extraSpriteConfig.BOSSSPRITE:IsPlaying(extraSpriteConfig.BOSSANIM) then
                    extraSpriteConfig.BOSSSPRITE:Update()
                    extraSpriteConfig.BOSSSPRITE:Render(AlphaAPI.getScreenCenterPosition(), VECTOR_ZERO, VECTOR_ZERO)
                end

                if extraSpriteConfig.TRANSITIONSPRITE:IsPlaying(extraSpriteConfig.TRANSITIONANIM) then
                    extraSpriteConfig.TRANSITIONSPRITE:Update()
                    extraSpriteConfig.TRANSITIONSPRITE:Render(AlphaAPI.getScreenCenterPosition(), VECTOR_ZERO, VECTOR_ZERO)
                end
            end
        end
    end

    function StageAPI.PlayNameStreak(extraSpriteConfig, isStageOne)
        if isStageOne then
            extraSpriteConfig.NAMESPRITE:ReplaceSpritesheet(0, extraSpriteConfig.NAME1)
        else
            extraSpriteConfig.NAMESPRITE:ReplaceSpritesheet(0, extraSpriteConfig.NAME2)
        end

        extraSpriteConfig.NAMESPRITE:Play(extraSpriteConfig.NAMEANIM, true)
    end

    function StageAPI.PlayBossAnimation(extraSpriteConfig, spot, portrait, name)
        if spot then
            extraSpriteConfig.BOSSSPRITE:ReplaceSpritesheet(2, spot)
        end

        if portrait then
            extraSpriteConfig.BOSSSPRITE:ReplaceSpritesheet(4, portrait)
        end

        if name then
            extraSpriteConfig.BOSSSPRITE:ReplaceSpritesheet(7, name)
        end

        extraSpriteConfig.BOSSSPRITE:LoadGraphics()
    	extraSpriteConfig.BOSSSPRITE:Play(extraSpriteConfig.BOSSANIM, true)
    end

    function StageAPI.PlayTransitionAnimation(extraSpriteConfig)
        extraSpriteConfig.TRANSITIONSPRITE:Play(extraSpriteConfig.TRANSITIONANIM, true)
    end

    function StageAPI.CheckForBoss(bossConfig, entities)
        entities = entities or AlphaAPI.entities.enemies
        local bossFound
        for _, ent in ipairs(entities) do
            local type, variant, subtype = ent.Type, ent.Variant, ent.SubType
            for _, boss in ipairs(bossConfig.BOSSES) do
                if (not boss.TYPE or boss.TYPE == type) and (not boss.VARIANT or boss.VARIANT == variant) and (not boss.SUBTYPE or boss.SUBTYPE == subtype) then
                    if not bossFound or not bossFound.PRIORITY then
                        bossFound = boss
                    elseif boss.PRIORITY and boss.PRIORITY > bossFound.PRIORITY then
                        bossFound = boss
                    end
                end
            end
        end

        return bossFound
    end

    function StageAPI.ChangeBackdrop(backdropConfig)
        local roomType = room:GetType()
        rng:SetSeed(room:GetDecorationSeed(), 0)
        local backdropVariants = backdropConfig.DATA[roomType] or backdropConfig.DATA["Default"]
        local backdropVariant = backdropVariants[random(#backdropVariants)]

        for i = 1, 2 do
            local npc = Isaac.Spawn(EntityType.ENTITY_EFFECT, 82, 0, VECTOR_ZERO, VECTOR_ZERO, nil)
            local sprite = npc:GetSprite()
            sprite:Load(anm2 or "stageapi/Backdrop.anm2", true)
            for num=0, 15 do
                local wall_to_use = backdropVariant.WALLS[random(#backdropVariant.WALLS)]
                sprite:ReplaceSpritesheet(num, wall_to_use)
            end

            local nfloor_to_use = backdropVariant.NFLOORS[random(#backdropVariant.NFLOORS)]
            local lfloor_to_use = backdropVariant.LFLOORS[random(#backdropVariant.LFLOORS)]
            local corner_to_use = backdropVariant.CORNERS[random(#backdropVariant.CORNERS)]
            sprite:ReplaceSpritesheet(16, nfloor_to_use)
            sprite:ReplaceSpritesheet(17, nfloor_to_use)
            sprite:ReplaceSpritesheet(18, lfloor_to_use)
            sprite:ReplaceSpritesheet(19, lfloor_to_use)
            sprite:ReplaceSpritesheet(20, lfloor_to_use)
            sprite:ReplaceSpritesheet(21, lfloor_to_use)
            sprite:ReplaceSpritesheet(22, lfloor_to_use)
            sprite:ReplaceSpritesheet(23, corner_to_use)

            npc.Position = room:GetTopLeftPos()+Vector(260,0)

            if room:GetRoomShape() == RoomShape.ROOMSHAPE_1x1 then sprite:Play("1x1_room", true)
            elseif room:GetRoomShape() ==  RoomShape.ROOMSHAPE_IH then sprite:Play("IH_room", true)
            elseif room:GetRoomShape() ==  RoomShape.ROOMSHAPE_IV then
                sprite:Play("IV_room", true)
                npc.Position = room:GetTopLeftPos()+Vector(113,0)
            elseif room:GetRoomShape() ==  RoomShape.ROOMSHAPE_1x2 then sprite:Play("1x2_room", true)
            elseif room:GetRoomShape() == RoomShape.ROOMSHAPE_IIV then
                sprite:Play("IIV_room", true)
                npc.Position = room:GetTopLeftPos()+Vector(113,0)
            elseif room:GetRoomShape() == RoomShape.ROOMSHAPE_2x1 then sprite:Play("2x1_room", true)
            elseif room:GetRoomShape() == RoomShape.ROOMSHAPE_IIH then sprite:Play("IIH_room", true)
            elseif room:GetRoomShape() == RoomShape.ROOMSHAPE_2x2 then sprite:Play("2x2_room", true)
            elseif room:GetRoomShape() == RoomShape.ROOMSHAPE_LTL then sprite:Play("LTL_room", true)
            elseif room:GetRoomShape() == RoomShape.ROOMSHAPE_LTR then sprite:Play("LTR_room", true)
            elseif room:GetRoomShape() == RoomShape.ROOMSHAPE_LBL then sprite:Play("LBL_room", true)
            elseif room:GetRoomShape() == RoomShape.ROOMSHAPE_LBR then sprite:Play("LBR_room", true) end
            sprite:LoadGraphics()
            if i == 1 then
                npc:ToEffect():AddEntityFlags(EntityFlag.FLAG_RENDER_FLOOR)
            else
                npc:ToEffect():AddEntityFlags(EntityFlag.FLAG_RENDER_WALL)
            end
        end
    end

    local musicMan = MusicManager()
    function StageAPI.GetMusicToPlay(musicConfig, key)
        local currentMusicID = musicMan:GetCurrentMusicID()
        local isPlaying = false
        for _, musicID in ipairs(musicConfig[key]) do
            if musicID == currentMusicID then
                isPlaying = true
            end
        end

        if not isPlaying then
            local musicID = musicConfig[key][random(#musicConfig[key])]
            return musicID
        end
    end

    function StageAPI.PlayMusic(musicConfig, force)
        local roomType = room:GetType()
        local currentMusicID = musicMan:GetCurrentMusicID()
        if currentMusicID ~= Music.MUSIC_GAME_OVER
        and currentMusicID ~= Music.MUSIC_GAME_OVER
        and currentMusicID ~= Music.MUSIC_JINGLE_GAME_OVER
        and currentMusicID ~= Music.MUSIC_JINGLE_GAME_START
        and currentMusicID ~= Music.MUSIC_JINGLE_NIGHTMARE then
            local selectedMusicID
            if not room:IsClear() and roomType == RoomType.ROOM_BOSS then
                if #musicConfig["Boss"] > 0 then
                    selectedMusicID = StageAPI.GetMusicToPlay(musicConfig, "Boss")
                else
                    selectedMusicID = Music.MUSIC_BOSS
                end
            elseif #musicConfig["UnclearedRoom"] > 0 and not room:IsClear() then
                selectedMusicID = StageAPI.GetMusicToPlay(musicConfig, "UnclearedRoom")
            elseif musicConfig[roomType] then
                selectedMusicID = StageAPI.GetMusicToPlay(musicConfig, roomType)
            elseif (roomType == RoomType.ROOM_DEFAULT or force) and musicConfig["Default"] then
                selectedMusicID = StageAPI.GetMusicToPlay(musicConfig, "Default")
            end

            if selectedMusicID then
                if currentMusicID ~= selectedMusicID then
                    if level:GetCurrentRoomIndex() == level:GetStartingRoomIndex() and room:GetFrameCount() == 1 then
                        musicMan:Fadein(selectedMusicID, 0.1)
                        musicMan:Queue(selectedMusicID)
                        musicMan:UpdateVolume()
                    else
                        musicMan:Play(selectedMusicID, 0.1)
                        musicMan:Queue(selectedMusicID)
                        musicMan:UpdateVolume()
                    end
                end

                if currentMusicID == selectedMusicID then
                    if musicMan:IsLayerEnabled() and room:IsClear() then
                        musicMan:DisableLayer()
                    elseif not music:IsLayerEnabled() and not room:IsClear() then
                        musicMan:EnableLayer()
                    end
                end
            end
        end
    end

    function StageAPI.IsInNewStage()
        for k, stage in pairs(StageAPI.Replace) do
            if AlphaAPI.tableContains(stage.STAGES, level:GetStage()) and AlphaAPI.tableContains(stage.STAGETYPES, level:GetStageType()) then
                return true, stage
            end
        end
    end
end

-- STAGEAPI ROOM CHOOSING AND INITIALIZATION FUNCTIONS --
do
    local gridData = {}
    function StageAPI.ClearRoomLayout(ignoreGrids)
    	for _, entity in ipairs(AlphaAPI.entities.enemies) do
            entity:Remove()
    	end

        for _, entity in ipairs(AlphaAPI.entities.friendly) do
            local type = entity.Type
            if type ~= EntityType.ENTITY_KNIFE and type ~= EntityType.ENTITY_PLAYER and type ~= EntityType.ENTITY_FAMILIAR then
                entity:Remove()
            end
        end

        if not ignoreGrids then
            for _, grid in ipairs(AlphaAPI.entities.grid) do
                if not grid:ToDoor() and not grid:ToWall() and not grid:ToDecoration() then
                    local index = grid:GetGridIndex()
                    AlphaAPI.callDelayed(function()
                        if not gridData[index] then
                            room:RemoveGridEntity(index, 0, false)
                        end
                    end, 1, true)
                end
            end
        end
    end

    function StageAPI.ChooseRoom(roomfile, seed, requiredEntityType, requiredEntityVariant, requiredEntitySubType, requiredGridType, requiredGridVariant)
        local difficulty = game.Difficulty
        local good_rooms = {}
        for _, roomdata in pairs(roomfile) do
            local goodroom = false
            local hasRequiredEntity = not requiredEntityType and not requiredEntityVariant and not requiredEntitySubType
            local hasRequiredGrid   = not requiredGridType and not requiredGridVariant
            if roomdata.SHAPE == room:GetRoomShape() then
                goodroom = true
                for _, object in ipairs(roomdata) do
                    if object.ISDOOR then
                        if object.EXISTS == nil and object.SLOT ~= nil then
                            if room:GetDoor(object.SLOT) ~= nil then
                                goodroom = false
                            end
                        end
                    elseif CorrectedGridTypes[object[1].TYPE] and requiredGridVariant or requiredGridType then
                        if (not requiredGridType or CorrectedGridTypes[object[1].TYPE] == requiredGridType) and (not requiredGridVariant or object[1].VARIANT == requiredGridVariant) then
                            hasRequiredGrid = true
                        end
                    elseif object[1].TYPE ~= 0 then
                        local type = object[1].TYPE
                        if type == 1400 or type == 1410 then
                            type = EntityType.ENTITY_FIREPLACE
                        end

                        if (not requiredEntityType or requiredEntityType == type) and (not requiredEntityVariant or requiredEntityVariant == object[1].VARIANT) and (not requiredEntitySubType or requiredEntitySubType == object[1].SUBTYPE) then
                            hasRequiredEntity = true
                        end
                    end
                end
            end

            if goodroom and (not hasRequiredEntity or not hasRequiredGrid) then
                goodroom = false
            end

            if goodroom then
                if difficulty == Difficulty.DIFFICULTY_NORMAL then
                    if roomdata.DIFFICULTY >= 15 then           -- Very Hard
                    elseif roomdata.DIFFICULTY >= 10 then       -- Hard
                        good_rooms[#good_rooms + 1] = roomdata
                    elseif roomdata.DIFFICULTY >= 5 then        -- Normal
                        good_rooms[#good_rooms + 1] = roomdata
                        good_rooms[#good_rooms + 1] = roomdata
                        good_rooms[#good_rooms + 1] = roomdata
                    else                                        -- Easy
                        good_rooms[#good_rooms + 1] = roomdata
                        good_rooms[#good_rooms + 1] = roomdata
                    end
                elseif difficulty == Difficulty.DIFFICULTY_HARD then
                    if roomdata.DIFFICULTY >= 15 then           -- Very Hard
                        good_rooms[#good_rooms + 1] = roomdata
                    elseif roomdata.DIFFICULTY >= 10 then       -- Hard
                        good_rooms[#good_rooms + 1] = roomdata
                        good_rooms[#good_rooms + 1] = roomdata
                    elseif roomdata.DIFFICULTY >= 5 then        -- Normal
                        good_rooms[#good_rooms + 1] = roomdata
                        good_rooms[#good_rooms + 1] = roomdata
                        good_rooms[#good_rooms + 1] = roomdata
                    else                                        -- Easy
                        good_rooms[#good_rooms + 1] = roomdata
                    end
                end
            end
        end

        if #good_rooms > 0 then
            rng:SetSeed(seed, 0)
            return good_rooms[random(#good_rooms)]
        end
    end

    function StageAPI.ChangeRoom(chosen, gridConfig, ignoreGrids)
        local grid_map = {}
        local grids_spawned = {}
        local ents_spawned = {}

        for _, object in ipairs(chosen) do
            if not object.ISDOOR then
                if CorrectedGridTypes[object[1].TYPE] then
                    grid_map[tostring(object.GRIDX) .. tostring(object.GRIDY)] = {
                        TYPE = CorrectedGridTypes[object[1].TYPE],
                        VARIANT = object[1].VARIANT,
                        GRIDY = object.GRIDY,
                        GRIDX = object.GRIDX
                    }
                elseif object[1].TYPE ~= 0 then
                    if object[1].TYPE == 1400 or object[1].TYPE == 1410 then object[1].TYPE = EntityType.ENTITY_FIREPLACE end
                    local npc = Isaac.Spawn(
                        object[1].TYPE,
                        object[1].VARIANT,
                        object[1].SUBTYPE,
                        room:GetGridPosition(VectorToGrid(object.GRIDX, object.GRIDY)),
                        VECTOR_ZERO,
                        nil
                    )
                    if npc:CanShutDoors() then room:SetClear(false) end
                    ents_spawned[#ents_spawned + 1] = npc
                end
            end
        end

        gridData = {}
        if not ignoreGrids then
            local seed = room:GetDecorationSeed()
            rng:SetSeed(seed, 0)
            for key, griddata in pairs(grid_map) do
                local index = VectorToGrid(griddata.GRIDX, griddata.GRIDY)
                room:RemoveGridEntity(index, 0, true)
                if gridConfig.ROCKREPLACECHANCES then
                    for _, rockChance in ipairs(gridConfig.ROCKREPLACECHANCES) do
                        if (rockChance.REPLACE == griddata.TYPE or rockChance.REPLACEALL) then
                            if random(0, rockChance.CHANCE) == 0 then
                                griddata.TYPE = rockChance.SPAWN
                            end
                        end
                    end
                elseif griddata.TYPE == GridEntityType.GRID_ROCK and index == room:GetTintedRockIdx() then
                    griddata.TYPE = GridEntityType.GRID_ROCKT
                end

                local grid = Isaac.GridSpawn(griddata.TYPE, griddata.VARIANT, room:GetGridPosition(index), true)
                gridData[grid:GetGridIndex()] = true
                grids_spawned[#grids_spawned + 1] = grid
                if grid then
                    grid:Init(seed)
                    grid:Update()
                    if grid:ToPit() then
                        StageAPI.InitPit(gridConfig, grid, seed, grid_map, griddata)
                    elseif grid:ToRock() then
                        StageAPI.ChangeRock(gridConfig, grid, seed)
                    end
                end
            end

            StageAPI.ResetPits(gridConfig, seed)
        end

        return ents_spawned, grids_spawned
    end

    function StageAPI.ChangeRoomLayout(roomfile, gridConfig, noRespectCleared, requiredEntityType, requiredEntityVariant, requiredEntitySubType, requiredGridType, requiredGridVariant)
        Isaac.DebugString("ChangeRoomLayout called")
        local index = level:GetCurrentRoomIndex()
        local chosen = StageAPI.ChooseRoom(roomfile, room:GetSpawnSeed(), requiredEntityType, requiredEntityVariant, requiredEntitySubType, requiredGridType, requiredGridVariant)
        Isaac.DebugString( "[StageAPI] Room of type " .. tostring(chosen.TYPE) .. " and variant " .. tostring(chosen.VARIANT) )
        if room:IsFirstVisit() or noRespectCleared then
            StageAPI.ClearRoomLayout()
            return StageAPI.ChangeRoom(chosen, gridConfig)
        elseif not StageAPI.RoomsCleared[index] then
            StageAPI.ClearRoomLayout(true)
            return StageAPI.ChangeRoom(chosen, gridConfig, true)
        end
    end

    function StageAPI.ChangeBossRoom(roomfile, extraSpriteConfig, bossConfig, gridConfig, noRespectCleared, spot, requiredEntityType, requiredEntityVariant, requiredEntitySubType, requiredGridType, requiredGridVariant)
        local ents_spawned = StageAPI.ChangeRoomLayout(roomfile, gridConfig, noRespectCleared, requiredEntityType, requiredEntityVariant, requiredEntitySubType, requiredGridType, requiredGridVariant)
        local bossData = StageAPI.CheckForBoss(bossConfig, ents_spawned)
        if bossData then
            StageAPI.PlayBossAnimation(extraSpriteConfig, bossData.SPOT, bossData.PORTRAIT, bossData.NAME)
        end
    end
end

-- ACTUAL STAGEAPI CALLBACKS & CODE --
do
    function mod:PostUpdate()
        if StageAPI.NextStage then
            --for _, Player in pairs(player) do
            --    if Player.Variant == 0 then
            local player = AlphaAPI.GAME_STATE.PLAYERS[1]
                    local sprite = Player:GetSprite()
                    if not trapdoorFound then
                        for _, grid in ipairs(AlphaAPI.entities.grid) do
                            if grid:ToTrapdoor() and Player.Position:Distance(grid.Position) < Player.Size + 32 then
                                if not sprite:IsPlaying("Trapdoor") and not (StageAPI.CurrentStage and StageAPI.CurrentStage.EXTRASPRITECONFIG and StageAPI.EXTRASPRITECONFIG.TRANSITIONSPRITE:IsPlaying("Scene")) and grid.Sprite:IsFinished("Opened") then
                                    Player:SetTargetTrapDoor(grid)
                                    Player:AnimateTrapdoor()
                                    Player.Velocity = VECTOR_ZERO
                                    Player.ControlsEnabled = false
                                    trapdoorFound = true
                                end
                            end
                        end
                    end

                    if sprite:IsPlaying("Trapdoor") and sprite:GetFrame() == 15 and trapdoorFound then
                        trapdoorFound = false
                        sprite:Stop()
                        if StageAPI.NextStage:IsInStage() or not StageAPI.NextStage.ISMULTISTAGE then
                            StageAPI.NextStage:MoveToStage(2)
                        else
                            StageAPI.NextStage:MoveToStage(1)
                        end

                        StageAPI.NextStage = nil
                    end
            --    end
            --end
        end

        if StageAPI.IsInNewStage() then
            local roomIndex = level:GetCurrentRoomIndex()
            if room:IsClear() and not StageAPI.RoomsCleared[roomIndex] then
                StageAPI.RoomsCleared[roomIndex] = true
            end

            for _, grid in ipairs(AlphaAPI.entities.grid) do
                StageAPI.CheckBridge(StageAPI.CurrentStage.GRIDCONFIG, grid)
            end
        end
    end

    mod:AddCallback(ModCallbacks.MC_POST_UPDATE, mod.PostUpdate)

    function mod:PostRender()
        if StageAPI.IsInNewStage() then
            StageAPI.RenderExtraSprites(StageAPI.CurrentStage.EXTRASPRITECONFIG)

            if StageAPI.CurrentStage.EXTRASPRITECONFIG.BOSSSPRITE:IsPlaying("Scene") then
                if Input.IsActionPressed(ButtonAction.ACTION_MENUCONFIRM, AlphaAPI.GAME_STATE.PLAYERS[1].ControllerIndex)  then
                    StageAPI.CurrentStage.EXTRASPRITECONFIG.BOSSSPRITE:Stop()
                end
            end

            if StageAPI.CurrentStage.EXTRASPRITECONFIG.TRANSITIONSPRITE:IsPlaying("Scene") then
                if Input.IsActionTriggered(ButtonAction.ACTION_MENUCONFIRM, AlphaAPI.GAME_STATE.PLAYERS[1].ControllerIndex) then
                    StageAPI.CurrentStage.EXTRASPRITECONFIG.TRANSITIONSPRITE:Stop()
                end
            elseif StageAPI.CurrentStage.EXTRASPRITECONFIG.TRANSITIONSPRITE:IsFinished("Scene") then
                StageAPI.PlayNameStreak(StageAPI.CurrentStage.EXTRASPRITECONFIG, (StageAPI.NextStage and StageAPI.NextStage:IsInStage()))
                    AlphaAPI.GAME_STATE.PLAYERS[1].ControlsEnabled = true
            end
        end
    end

    mod:AddCallback(ModCallbacks.MC_POST_RENDER, mod.PostRender)

    function mod:PostNewRoom()
        local roomType = room:GetType()
        if StageAPI.IsInNewStage() and not (level:GetCurrentRoomIndex() == level:GetStartingRoomIndex() and room:IsFirstVisit()) then
            if roomType == RoomType.ROOM_DEFAULT or roomType == RoomType.ROOM_TREASURE or roomType == RoomType.ROOM_BOSS or roomType == RoomType.ROOM_MINIBOSS then
                StageAPI.ChangeBackdrop(StageAPI.CurrentStage.BACKDROPCONFIG)
            end

            if roomType == RoomType.ROOM_DEFAULT then
                StageAPI.ChangeRoomLayout(StageAPI.CurrentStage.ROOMS, StageAPI.CurrentStage.GRIDCONFIG)
            end

            if roomType == RoomType.ROOM_BOSS then
                StageAPI.ChangeBossRoom(StageAPI.CurrentStage.BOSSROOMS, StageAPI.CurrentStage.EXTRASPRITECONFIG, StageAPI.CurrentStage.BOSSCONFIG, StageAPI.CurrentStage.GRIDCONFIG)
            end

            StageAPI.ChangeGridEntities(StageAPI.CurrentStage.GRIDCONFIG)
        end
    end

    mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, mod.PostNewRoom)

    function mod:PostNewLevel()
        StageAPI.CurrentStage = nil
        StageAPI.NextStage = StageAPI.NextNextStage
        StageAPI.NextNextStage = nil
        StageAPI.RoomsCleared = {}
        local isIn, stage = StageAPI.IsInNewStage()
        if isIn then
            AlphaAPI.GAME_STATE.PLAYERS[1]:AnimateAppear()
            --[[
            for _, Player in pairs(player) do
                if Player.Variant == 0 then
                    Player:AnimateAppear()
                end
            end]]

            if StageAPI.InitializingStage then
                StageAPI.CurrentStage = StageAPI.InitializingStage
            else
                StageAPI.CurrentStage = StageAPI.FloorsReplaced[stage.ID]
            end

            StageAPI.ChangeBackdrop(StageAPI.CurrentStage.BACKDROPCONFIG)
            StageAPI.ChangeGridEntities(StageAPI.CurrentStage.GRIDCONFIG)
        end
    end

    mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, mod.PostNewLevel)
end
