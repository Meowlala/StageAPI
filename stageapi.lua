StageAPI = { -- this is the core of pretty much everything so please don't hurt it.
    Version = 2.0
}

local stageAPIMod = RegisterMod("Stages Api", 1)
local api_mod = AlphaAPI.registerMod(stageAPIMod)
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

local transition = Sprite()
transition:Load("stageapi/customnightmare.anm2", true)
transition:Play("Idle", true)

local namestreak = Sprite()
namestreak:Load("gfx/ui/ui_streak.anm2", true)
namestreak:Play("TextStay", true)

local bossanim = Sprite()
bossanim:Load("stageapi/customversusscreen.anm2", true)

local rock_sprite = Sprite()
rock_sprite:Load("gfx/grid/grid_rock.anm2", true)

local pit_sprite = Sprite()
pit_sprite:Load("stageapi/pit.anm2", true)

local decoration_sprite = Sprite()
decoration_sprite:Load("gfx/grid/props_03_caves.anm2", true)

local door_sprite = Sprite()
door_sprite:Load("gfx/grid/door_01_normaldoor.anm2", true)

local rockanimations = {"normal", "black", "tinted", "alt", "bombrock", "big", "superspecial", "ss_broken"}

local function VectorToGrid(x,y)
	local room = AlphaAPI.GAME_STATE.ROOM
    local width = room:GetGridWidth()
    return width + 1 + (x + width * y)
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

local function CorrectGridType(Type)
    return CorrectedGridTypes[Type] or Type
end

local function TypeError(Function, Parameter, Expected, Got)
	if Expected ~= type(Got) then
		error("Error with "..Function..": Bad argument #"..tostring(Parameter).." (".. Expected .." expected, got "..type(Got)..")", 2)
		return false
	else return true end
end

local function getBackdropData(filenames)
    local backdrop_data = {}
    for index, variant in ipairs(filenames) do
        backdrop_data[index] = {
            NFLOORS = variant[1],
            LFLOORS = variant[2],
            CORNERS = variant[3],
            WALLS = variant[4],
            BOSS = variant[5]
        }
    end

    return backdrop_data
end

local CUSTOM_OVERLAYS = {}
local STAGES = {}
local stageProgression = {
    Current = nil,
    Set = nil,
    Next = nil
}


local StageObject = {}

function StageObject:MoveToStage(floor)
    if not floor then
        if self.ISMULTISTAGE then
            floor = 1
        else
            floor = 2
        end
    end

    for _, player in ipairs(AlphaAPI.GAME_STATE.PLAYERS) do
        player.ControlsEnabled = false
    end

    if floor == 1 then
        stageProgression.Set = self
        stageProgression.Next = self
        Isaac.ExecuteCommand("stage 3a")
    else
        stageProgression.Set = self
        stageProgression.Next = nil
        Isaac.ExecuteCommand("stage 4a")
    end

    transition:ReplaceSpritesheet(2, self.TRANSITIONICON or "stageapi/LevelIcon.png")
    transition:Play("Scene")
end

function StageObject:_init(name, rooms, bossrooms, isMultiStage)
    self.NAME = name
    self.ROOMS = rooms
    self.BOSSROOMS = bossrooms
    self.ISMULTISTAGE = isMultiStage
end

function StageObject:IsInStage()
    return stageProgression.Current and stageProgression.Current.NAME == self.NAME
end

function StageObject:SetRooms(rooms)
    self.ROOMS = rooms
end

function StageObject:SetBossRooms(rooms)
    self.BOSSROOMS = rooms
end

function StageObject:SetMultiStage(set)
    self.ISMULTISTAGE = set
end

function StageObject:SetNameSprite(pathfloor1, pathfloor2)
    self.NAMESPRITE = {FLOOR1 = pathfloor1, FLOOR2 = pathfloor2}
end

function StageObject:SetBackdrop(backdrop_data, anm2)
    self.BACKDROPS = backdrop_data
    self.BACKDROPANM2 = anm2 or "stageapi/Backdrop.anm2"
end

function StageObject:SetRocks(path, anm2)
    if anm2 then
        self.ROCKSPRITE = Sprite()
        self.ROCKSPRITE:Load(anm2, true)
    end

    self.ROCKS = path
end

function StageObject:SetPits(path, anm2)
    if anm2 then
        self.PITSPRITE = Sprite()
        self.PITSPRITE:Load(anm2, true)
    end

    self.PITS = path
end

function StageObject:SetBridges(path)
    self.BRIDGES = path
end

function StageObject:SetMusic(id)
    self.MUSIC = id
end

function StageObject:SetBossMusic(id)
    self.BOSSMUSIC = id
end

function StageObject:SetBossSpot(path)
    self.BOSSSPOT = path
end

function StageObject:SetDecoration(path, animBegin, anm2)
    animBegin = animBegin or "Prop"

    local sprite
    if anm2 then
        sprite = Sprite()
        sprite:Load(anm2, true)
    end

    self.DECORATION = {
        FILE = path,
        ANIM = animBegin,
        SPRITE = sprite
    }
end

function StageObject:SetDoors(sheet, anm2)
    if anm2 then
        self.DOORSPRITE = Sprite()
        self.DOORSPRITE:Load(anm2, true)
    end

    self.DOORS = sheet
end

function StageObject:SetTransitionIcon(path)
    self.TRANSITIONICON = path
end

function StageObject:SetBossPortrait(bossType, portraitFile, nameFile, bossVariant, bossSubtype, priority)
    if not bossType or not portraitFile then error("StageObject:SetBossPortrait requires an EntityType, a Portrait PNG file, and a Boss Name PNG file.", 2) end
    if not self.BOSSDATA then
        self.BOSSDATA = {}
    end

    self.BOSSDATA[#self.BOSSDATA + 1] = {
        ID = bossType,
        PORTRAIT = portraitFile,
        NAME = nameFile,
        VARIANT = bossVariant,
        SUBTYPE = bossSubtype,
        PRIORITY = priority
    }
end

function StageAPI.GetStageConfig(name, rooms, bossrooms, ismultistage)
    for _, stage in pairs(STAGES) do
        if stage.name == name then
            return stage
        end
    end

    local inst = {}
    setmetatable(inst, {__index = StageObject})
    inst:_init(name, rooms, bossrooms, ismultistage)

    STAGES[#STAGES + 1] = inst
    return inst
end

local backdrop_filenames = {
    {
        {
            "stageapi/backdrop/Catacombs1_nfloor.png"
        },
        {
            "stageapi/backdrop/Catacombs1_lfloor.png"
        },
        {
            "stageapi/backdrop/Catacombs1_corner.png"
        },
        {
            "stageapi/backdrop/Catacombs1_1.png",
            "stageapi/backdrop/Catacombs1_2.png"
        }
    },
    {
        {
            "stageapi/backdrop/Catacombs2_nfloor.png"
        },
        {
            "stageapi/backdrop/Catacombs2_lfloor.png"
        },
        {
            "stageapi/backdrop/Catacombs2_corner.png"
        },
        {
            "stageapi/backdrop/Catacombs2_1.png",
            "stageapi/backdrop/Catacombs2_2.png"
        }
    }
}

local catacomb_rooms = require("catacombs.lua")
local catacomb_boss_rooms = require("catacombsbosses.lua")
local catacombs_stage = StageAPI.GetStageConfig("Catacombs", catacomb_rooms, catacomb_boss_rooms, false)

catacombs_stage:SetTransitionIcon("stageapi/LevelIcon.png")

catacombs_stage:SetNameSprite("stageapi/effect_catacombs1_streak.png", "stageapi/effect_catacombs2_streak.png")
catacombs_stage:SetBackdrop(getBackdropData(backdrop_filenames))

catacombs_stage:SetBridges("gfx/grid/grid_bridge_catacombs.png")
catacombs_stage:SetPits("gfx/grid/grid_pit_catacombs.png")
catacombs_stage:SetRocks("gfx/grid/rocks_catacombs.png")

catacombs_stage:SetMusic(Music.MUSIC_CATACOMBS)

catacombs_stage:SetBossSpot("gfx/ui/boss/bossspot_04_catacombs.png")

local bosses = {
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

for _, bossdata in ipairs(bosses) do
    catacombs_stage:SetBossPortrait(bossdata[1], "gfx/ui/boss/portrait_" .. bossdata[2] .. ".png", "gfx/ui/boss/bossname_" .. bossdata[2] .. ".png", bossdata[3], bossdata[4])
end

local gridData = {

}

function StageAPI.ClearRoomLayout()
	for _, entity in ipairs(AlphaAPI.entities.all) do
		if entity.Type ~= EntityType.ENTITY_PLAYER and entity.Type ~= EntityType.ENTITY_FAMILIAR and entity.Type ~= EntityType.ENTITY_KNIFE and not (entity.Type == 1000 and (entity.Variant == 82 or entity.Variant == 8)) then
            entity:Remove()
        end
	end

    for _, grid in ipairs(AlphaAPI.entities.grid) do
        if not grid:ToDoor() and not grid:ToWall() and not grid:ToDecoration() then
            local index = grid:GetGridIndex()
            AlphaAPI.callDelayed(function()
                if not gridData[index] then
                    AlphaAPI.GAME_STATE.ROOM:RemoveGridEntity(index, 0, false)
                end
            end, 1, true)
        end
    end
end

local function isPit(map, gridx, gridy)
    local point = map[tostring(gridx) .. tostring(gridy)]
    if point then
        return point.TYPE == GridEntityType.GRID_PIT
    end
end

-- Takes whether or not there is a pit in each adjacent space, returns frame to set pit sprite to.
function StageAPI.getPitSprite(L, R, U, D, UL, DL, UR, DR)
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

function StageAPI.ChangeRoomLayout(roomfile, Type)
	if TypeError("ChangeRoomLayout", 1, "table", roomfile) then
		local game = Game()
		local room = game:GetRoom()
		local level = game:GetLevel()
        local difficulty = game.Difficulty

        local good_rooms = {}
        for _, roomdata in pairs(roomfile) do
            local goodroom = false
			if roomdata.SHAPE == room:GetRoomShape() and (not Type or roomdata.TYPE == Type) then
				goodroom = true
				for i=1, #roomdata do
					if roomdata[i].ISDOOR then
						if roomdata[i].EXISTS == nil and roomdata[i].SLOT ~= nil then
							if room:GetDoor(roomdata[i].SLOT) ~= nil then
								goodroom = false
							end
						end
					end
				end
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
            local grid_map = {}

            rng:SetSeed(room:GetSpawnSeed(), 1)
            local chosen = good_rooms[random(#good_rooms)]

            local grids_spawned = {}
            local ents_spawned = {}

			for _, entitydata in ipairs(chosen) do
				if not entitydata.ISDOOR then
					if CorrectedGridTypes[entitydata[1].TYPE] then
                        grid_map[tostring(entitydata.GRIDX) .. tostring(entitydata.GRIDY)] = {
                            TYPE = CorrectGridType(entitydata[1].TYPE),
                            VARIANT = entitydata[1].VARIANT,
                            GRIDY = entitydata.GRIDY,
                            GRIDX = entitydata.GRIDX
                        }
					elseif entitydata[1].TYPE ~= 0 then
						if entitydata[1].TYPE == 1400 or entitydata[1].TYPE == 1410 then entitydata[1].TYPE = EntityType.ENTITY_FIREPLACE end
						local npc = Isaac.Spawn(
                            entitydata[1].TYPE,
                            entitydata[1].VARIANT,
                            entitydata[1].SUBTYPE,
                            room:GetGridPosition(VectorToGrid(entitydata.GRIDX, entitydata.GRIDY)),
                            VECTOR_ZERO,
                            nil
                        )
                        ents_spawned[#ents_spawned + 1] = npc
						if npc:CanShutDoors() then
							room:SetClear(false)
							for num=0, 7 do
								if room:GetDoor(num) ~= nil then
									room:GetDoor(num):Close(true)
								end
							end
						end
					end
				end
			end

            gridData = {}
            for key, griddata in pairs(grid_map) do
                local grid = Isaac.GridSpawn(griddata.TYPE, griddata.VARIANT, room:GetGridPosition(VectorToGrid(griddata.GRIDX, griddata.GRIDY)), true)
                gridData[grid:GetGridIndex()] = true
                grids_spawned[#grids_spawned + 1] = grid
                if grid then
                    grid:Init(room:GetDecorationSeed())
                    grid:Update()
                    if grid:ToPit() then
                        -- Words were shortened to make writing code simpler.
                        local L = isPit(grid_map, griddata.GRIDX - 1, griddata.GRIDY) -- Left Pit
                        local R = isPit(grid_map, griddata.GRIDX + 1, griddata.GRIDY) -- Right Pit
                        local U = isPit(grid_map, griddata.GRIDX, griddata.GRIDY - 1) -- Up Pit
                        local D = isPit(grid_map, griddata.GRIDX, griddata.GRIDY + 1) -- Down Pit
                        local UL = isPit(grid_map, griddata.GRIDX - 1, griddata.GRIDY - 1) -- Up Left Pit
                        local DL = isPit(grid_map, griddata.GRIDX - 1, griddata.GRIDY + 1) -- Down Left Pit
                        local UR = isPit(grid_map, griddata.GRIDX + 1, griddata.GRIDY - 1) -- Up Right Pit
                        local DR = isPit(grid_map, griddata.GRIDX + 1, griddata.GRIDY + 1) -- Down Right Pit

                        local F = StageAPI.getPitSprite(L, R, U, D, UL, DL, UR, DR)

                        local spriteToUse = pit_sprite
                        if stageProgression.Current then
                            if stageProgression.Current.PITSPRITE then
                                spriteToUse = stageProgression.Current.PITSPRITE
                            end
                        end

                        if StageAPI.InNewStage() then
                            for num=0, 4 do
                                spriteToUse:ReplaceSpritesheet(num, stageProgression.Current.PITS or "gfx/grid/grid_pit.png")
                            end
                        end

                        spriteToUse:LoadGraphics()
                        spriteToUse:SetFrame("pit", F)

                        grid.Sprite = pit_sprite
                    elseif grid:ToRock() then
                        local spriteToUse = rock_sprite
                        if stageProgression.Current then
                            if stageProgression.Current.ROCKSPRITE then
                                spriteToUse = stageProgression.Current.ROCKSPRITE
                            end
                        end

                        if StageAPI.InNewStage() then
                            for num=0, 4 do
                                spriteToUse:ReplaceSpritesheet(num, stageProgression.Current.ROCKS or "gfx/grid/rocks_catacombs.png")
                            end
                        end

                        for rock = 1, #rockanimations do
                            if grid.Sprite:IsPlaying(rockanimations[rock]) or grid.Sprite:IsFinished(rockanimations[rock]) then
                                spriteToUse:SetFrame(rockanimations[rock], grid.Sprite:GetFrame())
                            end
                        end

                        spriteToUse:LoadGraphics()
                        grid.Sprite = spriteToUse
                    end
                end
            end

            return ents_spawned, grids_spawned
		end
	end
end

function StageAPI.ChangeBackdrop(backdrop_data, anm2)
	local room = AlphaAPI.GAME_STATE.ROOM
	if TypeError("ChangeBackdrop", 1, "table", backdrop_data) then
        rng:SetSeed(room:GetDecorationSeed(), 1)
        local backdrop_variant = backdrop_data[random(#backdrop_data)]

        for i = 1, 2 do
            local npc = Isaac.Spawn(EntityType.ENTITY_EFFECT, 82, 0, VECTOR_ZERO, VECTOR_ZERO, nil)
            local sprite = npc:GetSprite()
            sprite:Load(anm2 or "stageapi/Backdrop.anm2", true)
            if room:GetType() ~= RoomType.ROOM_BOSS or not backdrop_variant.BOSS then
                for num=0, 15 do
                    local wall_to_use = backdrop_variant.WALLS[random(#backdrop_variant.WALLS)]
                    sprite:ReplaceSpritesheet(num, wall_to_use)
                end
            else
                for num=0, 15 do
                    local wall_to_use = backdrop_variant.BOSS[random(#backdrop_variant.BOSS)]
                    sprite:ReplaceSpritesheet(num, wall_to_use)
                end
            end

            local nfloor_to_use = backdrop_variant.NFLOORS[random(#backdrop_variant.NFLOORS)]
            local lfloor_to_use = backdrop_variant.LFLOORS[random(#backdrop_variant.LFLOORS)]
            local corner_to_use = backdrop_variant.CORNERS[random(#backdrop_variant.CORNERS)]
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
end

function StageAPI.ChangeDoors(FileNameDoor, sprite)
	local room = AlphaAPI.GAME_STATE.ROOM
    sprite = sprite or stageProgression.Current.DOORSPRITE or door_sprite
    if sprite then
        sprite:ReplaceSpritesheet(0, FileNameDoor)
        for i=0, DoorSlot.NUM_DOOR_SLOTS-1 do
            local door = room:GetDoor(i)
            if door ~= nil then
                if room:GetType() == RoomType.ROOM_DEFAULT or room:GetType() == RoomType.ROOM_MINIBOSS or room:GetType() == RoomType.ROOM_SACRIFICE then
                    if door.TargetRoomType == RoomType.ROOM_DEFAULT or door.TargetRoomType == RoomType.ROOM_MINIBOSS or door.TargetRoomType == RoomType.ROOM_SACRIFICE then
                        sprite.Rotation = i*90-90
                        door.Sprite = sprite
                    end
                end
            end
        end
    end
end

function StageAPI.ChangePits(FileNamePit, FileNameBridge, sprite)
	if TypeError("ChangeBridges", 1, "string", FileNamePit) and TypeError("ChangeBridges", 2, "string", FileNameBridge) then
		for _, grid in ipairs(AlphaAPI.entities.grid) do
			if grid:ToPit() then
                local spriteToUse = sprite or pit_sprite
                if stageProgression.Current and not sprite then
                    if stageProgression.Current.PITSPRITE then
                        spriteToUse = stageProgression.Current.PITSPRITE
                    end
                end

				spriteToUse:ReplaceSpritesheet(0, FileNamePit)
				spriteToUse:SetFrame("pit", grid.Sprite:GetFrame())
				if grid.State == 1 then
					spriteToUse:ReplaceSpritesheet(1, FileNameBridge)
					spriteToUse:SetOverlayFrame("Bridge", 0)
				end
				spriteToUse:LoadGraphics()
				grid.Sprite = spriteToUse
			end
		end
	end
end

function StageAPI.ChangeRocks(FileName, sprite)
	if TypeError("ChangeRocks", 1, "string", FileName) then
		for _, grid in ipairs(AlphaAPI.entities.grid) do
			if grid:ToRock() then
                local spriteToUse = sprite or rock_sprite
                if stageProgression.Current and not sprite then
                    if stageProgression.Current.ROCKSPRITE then
                        spriteToUse = stageProgression.Current.ROCKSPRITE
                    end
                end

                for num=0, 4 do
                    spriteToUse:ReplaceSpritesheet(num, rockFileName)
                end

                for rock = 1, #rockanimations do
                    if grid.Sprite:IsPlaying(rockanimations[rock]) or grid.Sprite:IsFinished(rockanimations[rock]) then
                        spriteToUse:SetFrame(rockanimations[rock], grid.Sprite:GetFrame())
                    end
                end

                spriteToUse:LoadGraphics()
                grid.Sprite = spriteToUse
			end
		end
	end
end

function StageAPI.ChangeGridEnts(rockFileName, pitFileName, decoData, pitSpriteOverride, rockSpriteOverride, decoSpriteOverride)
    for _, grid in ipairs(AlphaAPI.entities.grid) do
        if grid:ToPit() and pitFileName then
            local spriteToUse = pitSpriteOverride or pit_sprite
            if stageProgression.Current and not pitSpriteOverride then
                if stageProgression.Current.PITSPRITE then
                    spriteToUse = stageProgression.Current.PITSPRITE
                end
            end

            for num=0, 4 do
                spriteToUse:ReplaceSpritesheet(num, pitFileName)
            end
            spriteToUse:SetFrame("pit", grid.Sprite:GetFrame())
            spriteToUse:LoadGraphics()
            grid.Sprite = spriteToUse
        elseif grid:ToRock() and rockFileName then
            local spriteToUse = rockSpriteOverride or rock_sprite
            if stageProgression.Current and not rockSpriteOverride then
                if stageProgression.Current.ROCKSPRITE then
                    spriteToUse = stageProgression.Current.ROCKSPRITE
                end
            end

            for num=0, 4 do
                spriteToUse:ReplaceSpritesheet(num, rockFileName)
            end

            for rock = 1, #rockanimations do
                if grid.Sprite:IsPlaying(rockanimations[rock]) or grid.Sprite:IsFinished(rockanimations[rock]) then
                    spriteToUse:SetFrame(rockanimations[rock], grid.Sprite:GetFrame())
                end
            end

            spriteToUse:LoadGraphics()
            grid.Sprite = spriteToUse
        elseif grid:ToDecoration() and decoData and room:GetType() ~= RoomType.ROOM_DUNGEON then
            local spriteToUse = decoSpriteOverride or decoData.SPRITE or decoration_sprite

            spriteToUse:ReplaceSpritesheet(0, decoData.FILE)
            rng:SetSeed(room:GetDecorationSeed())
            local rand = random(1,42)
            if rand < 10 then rand = "0"..tostring(rand) end
            spriteToUse:Play(decoData.ANIM..tostring(rand), true)
            spriteToUse:LoadGraphics()
            grid.Sprite = spriteToUse
        end
    end
end

function StageAPI.GetCurrentBackdrop(anm2)
	for _, entity in ipairs(AlphaAPI.entities.effects) do
        local sprite = entity:GetSprite()
		if sprite:GetFilename() == (anm2 or "gfx/backdrop/Backdrop.anm2") then
			return sprite
		end
	end
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

function Overlay:Render()
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
        CUSTOM_OVERLAYS[#CUSTOM_OVERLAYS + 1] = overlay
        return overlay
	end
end

function StageAPI.GetStagesCount()
	return #STAGES
end

function StageAPI.PlayBossIntro(portrait, name, bossspot)
	bossanim:Play("Scene", true)

    bossanim:ReplaceSpritesheet(2, bossspot or "gfx/ui/boss/bossspot.png")
    bossanim:ReplaceSpritesheet(4, portrait)
    bossanim:ReplaceSpritesheet(7, name)
    bossanim:LoadGraphics()
end

function StageAPI.GetCurrentStage()
	return stageProgression.Current
end

function StageAPI.InNewStage()
    local stage = AlphaAPI.GAME_STATE.LEVEL:GetStage()
    return (stage == LevelStage.STAGE2_1 or stage == LevelStage.STAGE2_2) and AlphaAPI.GAME_STATE.LEVEL:GetStageType() == StageType.STAGETYPE_WOTL
end

function stageAPIMod:SettingUpStage1()
    for _, overlay in ipairs(CUSTOM_OVERLAYS) do
        overlay.Sprite:Update()
        overlay.Sprite:LoadGraphics()
	end

	local game = AlphaAPI.GAME_STATE.GAME
	local room = AlphaAPI.GAME_STATE.ROOM
	local level = AlphaAPI.GAME_STATE.LEVEL
    local curStage = stageProgression.Current

	for _, grid in ipairs(AlphaAPI.entities.grid) do
		if grid:ToPit() ~= nil and grid.State == 1 and not (grid.Sprite:IsOverlayPlaying("Bridge") or grid.Sprite:IsOverlayFinished("Bridge")) then
			pit_sprite:ReplaceSpritesheet(0, curStage.PITS)
			pit_sprite:SetFrame("pit", grid.Sprite:GetFrame())
			pit_sprite:ReplaceSpritesheet(1, curStage.BRIDGES)
			pit_sprite:SetOverlayFrame("Bridge", 0)
			pit_sprite:LoadGraphics()
			grid.Sprite = pit_sprite
		end
	end
end

local music = MusicManager()
local updateTick = false
local wait = 0
local trapdoorFound

function stageAPIMod:SettingUpStage2()
    stageProgression.Next = catacombs_stage
    for _, player in ipairs(AlphaAPI.GAME_STATE.PLAYERS) do
        if stageProgression.Next then
            local sprite = player:GetSprite()

            if not trapdoorFound then
                for _, grid in ipairs(AlphaAPI.entities.grid) do
                    if grid:ToTrapdoor() and player.Position:Distance(grid.Position) < player.Size + 32 then
                        if not sprite:IsPlaying("Trapdoor") and not transition:IsPlaying("Scene") then
                            player:AnimateTrapdoor()
                            player.SpriteOffset = (grid.Position - player.Position)
                            --player.SpriteOffset.X = player.SpriteOffset.X - player.Size / 2
                            player.Velocity = VECTOR_ZERO
                            player.ControlsEnabled = false
                            trapdoorFound = true
                        end
                    end
                end
            end

            if sprite:IsPlaying("Trapdoor") and sprite:GetFrame() == 15 and trapdoorFound then
                trapdoorFound = false
                sprite:Stop()
                player.SpriteOffset = VECTOR_ZERO
                if stageProgression.Next:IsInStage() or not stageProgression.Next.ISMULTISTAGE then
                    stageProgression.Next:MoveToStage(2)
                else
                    stageProgression.Next:MoveToStage(1)
                end
            end
        end
    end

    if StageAPI.InNewStage() then
        local game = AlphaAPI.GAME_STATE.GAME
        local room = AlphaAPI.GAME_STATE.ROOM
        local level = AlphaAPI.GAME_STATE.LEVEL
        local player = AlphaAPI.GAME_STATE.PLAYERS[1]

        local curStage = stageProgression.Current

        updateTick = not updateTick

        if namestreak:IsPlaying("Text") then
            if updateTick then
                namestreak:Update()
            end

            if namestreak:IsFinished("Text") then
                namestreak:Play("TextStay")
            end

            namestreak:Render(AlphaAPI.getScreenCenterPosition()+Vector(0,-80), VECTOR_ZERO, VECTOR_ZERO)
        end

        if bossanim:IsPlaying("Scene") then
            if Input.IsActionPressed(ButtonAction.ACTION_MENUCONFIRM, player.ControllerIndex) or bossanim:IsFinished("Scene") then
                bossanim:Stop()
            end

            if updateTick then
                bossanim:Update()
            end

            bossanim:Render(AlphaAPI.getScreenCenterPosition(), VECTOR_ZERO, VECTOR_ZERO)
        end

        if wait > 0 then wait = wait - 1 end

        if transition:IsPlaying("Scene") then
            if updateTick then
                transition:Update()
            end

            if (wait <= 0 and Input.IsActionTriggered(ButtonAction.ACTION_MENUCONFIRM, player.ControllerIndex)) or transition:IsFinished("Scene") then
                transition:Stop()
                transition:Play("Idle")

                if level:GetStage() == LevelStage.STAGE2_1 and curStage.NAMESPRITE.FLOOR1 ~= nil then
                    namestreak:ReplaceSpritesheet(0, curStage.NAMESPRITE.FLOOR1)
                elseif level:GetStage() == LevelStage.STAGE2_2 and curStage.NAMESPRITE.FLOOR2 ~= nil then
                    namestreak:ReplaceSpritesheet(0, curStage.NAMESPRITE.FLOOR2)
                end

                namestreak:ReplaceSpritesheet(1, "stageapi/none.png")
                namestreak:Play("Text")

                for _, player in ipairs(AlphaAPI.GAME_STATE.PLAYERS) do
                    player.ControlsEnabled = true
                end
            end

            transition:Render(AlphaAPI.getScreenCenterPosition(), VECTOR_ZERO, VECTOR_ZERO)
        end

		local musicid = curStage.MUSIC
        local currentMusicID = music:GetCurrentMusicID()
		if musicid then
			if currentMusicID ~= musicid
            and room:GetType() == RoomType.ROOM_DEFAULT
            and (level:GetCurrentRoomIndex() ~= level:GetStartingRoomIndex() or not room:IsFirstVisit())
            and currentMusicID ~= Music.MUSIC_GAME_OVER
            and currentMusicID ~= Music.MUSIC_JINGLE_GAME_OVER
            and currentMusicID ~= Music.MUSIC_JINGLE_GAME_START
            and currentMusicID ~= Music.MUSIC_JINGLE_NIGHTMARE then
				music:Play(musicid, 0.1)
				music:Queue(musicid)
				music:UpdateVolume()
			end

			if level:GetCurrentRoomIndex() == level:GetStartingRoomIndex() and room:GetFrameCount() == 1 then
				music:Fadein(musicid, 0.1)
				music:Queue(musicid)
				music:UpdateVolume()
			end

            if music:GetCurrentMusicID() == musicid then
                if music:IsLayerEnabled() and room:IsClear() then
                    music:DisableLayer()
                elseif not music:IsLayerEnabled() and not room:IsClear() then
                    music:EnableLayer()
                end
            end
		end

        if room:GetType() == RoomType.ROOM_BOSS and not room:IsClear() then
            local musicid = curStage.BOSSMUSIC or Music.MUSIC_BOSS
            if musicid and music:GetCurrentMusicID() ~= musicid then
                music:Play(musicid, 0.1)
                music:Queue(musicid)
                music:UpdateVolume()
            end
        end
	end
end

function stageAPIMod:OnNewRoom()
	local room = AlphaAPI.GAME_STATE.ROOM
    local level = AlphaAPI.GAME_STATE.LEVEL

	if StageAPI.InNewStage() then
        local curStage = stageProgression.Current

        if not (level:GetCurrentRoomIndex() == level:GetStartingRoomIndex() and room:IsFirstVisit()) then
    		if room:GetType() == RoomType.ROOM_DEFAULT or room:GetType() == RoomType.ROOM_TREASURE or room:GetType() == RoomType.ROOM_BOSS or room:GetType() == RoomType.ROOM_MINIBOSS then
    			if #curStage.BACKDROPS ~= 0 then
                    StageAPI.ChangeBackdrop(curStage.BACKDROPS, curStage.BACKDROPANM2)
    			end

                StageAPI.ChangeDoors(curStage.DOORS or "gfx/grid/door_01_normaldoor.png")

    			if room:IsFirstVisit() and room:GetType() == RoomType.ROOM_DEFAULT then
    				StageAPI.ChangeRoomLayout(curStage.ROOMS)
    			end

                StageAPI.ChangeGridEnts(curStage.ROCKS, curStage.PITS, curStage.DECORATION)
    		end
        end

        if room:IsFirstVisit() and room:GetType() == RoomType.ROOM_BOSS then
            local ents_spawned
            if curStage.BOSSROOMS then
                StageAPI.ClearRoomLayout()
                ents_spawned = StageAPI.ChangeRoomLayout( curStage.BOSSROOMS or catacombs_boss_rooms )
            end

            if ents_spawned then
                local bossSpawnedData = {}
                for _, entity in ipairs(ents_spawned) do
                    for _, bossdata in ipairs( curStage.BOSSDATA ) do
                        if (not bossdata.ID or entity.Type == bossdata.ID)
                        and (not bossdata.VARIANT or entity.Variant == bossdata.VARIANT)
                        and (not bossdata.SUBTYPE or entity.SubType == bossdata.SUBTYPE) then
                            bossSpawnedData[#bossSpawnedData + 1] = bossdata
                        end
                    end
                end

                if #bossSpawnedData > 1 then
                    local bossPlayData
                    for _, bossdata in ipairs(bossSpawnedData) do
                        if bossdata.PRIORITY then
                            if bossPlayData.PRIORITY then
                                if bossPlayData.PRIORITY < bossdata.PRIORITY then
                                    bossPlayData = bossdata
                                end
                            else
                                bossPlayData = bossdata
                            end
                        end

                        if not bossPlayData then
                            bossPlayData = bossdata
                        end
                    end

                    StageAPI.PlayBossIntro(bossPlayData.PORTRAIT, bossPlayData.NAME, curStage.BOSSSPOT)
                elseif #bossSpawnedData == 1 then
                    StageAPI.PlayBossIntro(bossSpawnedData[1].PORTRAIT, bossSpawnedData[1].NAME, curStage.BOSSSPOT)
                end
            end
        end
	end
end

function stageAPIMod:OnNewLevel()
    stageProgression.Current = nil

	if StageAPI.InNewStage() then
        for _, player in pairs(AlphaAPI.GAME_STATE.PLAYERS) do
            if player.Variant == 0 then
                player:AnimateAppear()
            end
        end

        if stageProgression.Set then
            stageProgression.Current = stageProgression.Set
            stageProgression.Set = stageProgression.Next
            stageProgression.Next = nil
        else
            stageProgression.Current = catacombs_stage
        end

        StageAPI.ChangeBackdrop(stageProgression.Current.BACKDROPS, stageProgression.Current.BACKDROPANM2)
        StageAPI.ChangeDoors(stageProgression.Current.DOORS or "gfx/grid/door_01_normaldoor.png")
	end
end

function stageAPIMod:ExecuteCommand(command, params)
    if command == "customstage" or command == "cstage" then
        local moved = false
        for _, stage in pairs(STAGES) do
            if string.lower(stage.NAME) == string.lower(params) then
                stage:moveToStage()
                Isaac.ConsoleOutput("Moving to stage " .. stage.NAME)
                moved = true
                wait = 60
                break
            end
        end

        if not moved then
            Isaac.ConsoleOutput("Could not find stage " .. params .. " to move to.")
        end
    end
end

stageAPIMod:AddCallback(ModCallbacks.MC_EXECUTE_CMD, stageAPIMod.ExecuteCommand)
stageAPIMod:AddCallback(ModCallbacks.MC_POST_UPDATE, stageAPIMod.SettingUpStage1)
stageAPIMod:AddCallback(ModCallbacks.MC_POST_RENDER, stageAPIMod.SettingUpStage2)

api_mod:addCallback(AlphaAPI.Callbacks.ROOM_CHANGED, stageAPIMod.OnNewRoom)
api_mod:addCallback(AlphaAPI.Callbacks.FLOOR_CHANGED, stageAPIMod.OnNewLevel)
