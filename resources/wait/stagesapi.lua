local flooranim = Sprite()
flooranim:Load("gfx/ui/stage/customnightmare.anm2")
flooranim:Play("Idle", true)

StageSystem = {  -- Changed GotoNewStage() and added SetStageIcon()
	GotoNewStage = function(StageId, Floor)
		Floor = Floor or 1
		if TypeError("GotoNewStage", 1, 0, StageId) and TypeError("GotoNewStage", 2, 0, Floor) then
			local level = AlphaAPI.GAME_STATE.LEVEL
			REVEL.game:GetSeeds():SetStartSeed("")
			StageSystem.nextstage = StageId
			Isaac.ExecuteCommand("stage "..tostring(Floor+2).."a")
			if CUSTOM_STAGES[StageId].ICON ~= nil then
				flooranim:ReplaceSpritesheet(2, "gfx/ui/stage/"..CUSTOM_STAGES[StageSystem.currentstage].ICON)
			else flooranim:ReplaceSpritesheet(2, "gfx/ui/stage/LevelIcon.png") end
			flooranim:Play("Scene", true)
		end
	end,
	
	SetStageIcon = function(StageId, FileName)
		if TypeError("FileName", 1, '', FileName) then
			CUSTOM_STAGES[StageId].ICON = FileName
		end
	end,
}

StageSystem.GetStage = function(StageId) -- Stage.SetIcon() and Stage.GetIcon()
	return {
		SetIcon = function(FileName) return StageSystem.SetStageIcon(StageId, FileName) end,
		GetIcon = function() return CUSTOM_STAGES[StageId].ICON end,
	}
end

function stagesystem:Update() -- POST_UPDATE
	flooranim:Update()
	flooranim:LoadGraphics()
	if namestreak:IsFinished("Text") then namestreak:Play("TextStay") end
end

function stagesystem:Render() -- POST_RENDER
	if namestreak:IsPlaying("Text") then
		if StageSystem.currentstage ~= 0 then namestreak:Render(getScreenCenterPosition()+Vector(0,-75), Vector(0,0), Vector(0,0))
		else namestreak:Render(getScreenCenterPosition()+Vector(0,75), Vector(0,0), Vector(0,0)) end
	end
	if (level:GetStage() == LevelStage.STAGE2_1 or level:GetStage() == LevelStage.STAGE2_2) and level:GetStageType() == StageType.STAGETYPE_WOTL then
		if flooranim:IsFinished("Scene") or Input.IsActionPressed(ButtonAction.ACTION_MENUCONFIRM, REVEL.player.ControllerIndex) then
			flooranim:Play("Idle", true)
			if level:GetStage() == LevelStage.STAGE2_1 and CUSTOM_STAGES[StageSystem.currentstage].NAMESPRITE.FLOOR1 ~= nil then
				namestreak:ReplaceSpritesheet(0, "gfx/ui/"..CUSTOM_STAGES[StageSystem.currentstage].NAMESPRITE.FLOOR1)
			elseif level:GetStage() == LevelStage.STAGE2_2 and CUSTOM_STAGES[StageSystem.currentstage].NAMESPRITE.FLOOR2 ~= nil then
				namestreak:ReplaceSpritesheet(0, "gfx/ui/"..CUSTOM_STAGES[StageSystem.currentstage].NAMESPRITE.FLOOR2)
			end
			namestreak:ReplaceSpritesheet(1, "gfx/ui/none.png")
			namestreak:Play("Text", true)
			REVEL.player.ControlsEnabled = true
		end
		if flooranim:IsPlaying("Scene") then
			REVEL.player.ControlsEnabled = false
			for i=0, flooranim:GetLayerCount() do
				flooranim:RenderLayer(i, getScreenCenterPosition())
			end
		end
	end
end

function stagesystem:OnNewLevel() -- POST_NEW_LEVEL
	if (level:GetStage() == LevelStage.STAGE2_1 or level:GetStage() == LevelStage.STAGE2_2) and level:GetStageType() == StageType.STAGETYPE_WOTL and StageSystem.currentstage == 0 then
		if level:GetStage() == LevelStage.STAGE2_1 and CUSTOM_STAGES[StageSystem.currentstage].NAMESPRITE.FLOOR1 ~= nil then
			namestreak:ReplaceSpritesheet(0, "gfx/ui/"..CUSTOM_STAGES[StageSystem.currentstage].NAMESPRITE.FLOOR1)
		elseif level:GetStage() == LevelStage.STAGE2_2 and CUSTOM_STAGES[StageSystem.currentstage].NAMESPRITE.FLOOR2 ~= nil then
			namestreak:ReplaceSpritesheet(0, "gfx/ui/"..CUSTOM_STAGES[StageSystem.currentstage].NAMESPRITE.FLOOR2)
		end
		namestreak:ReplaceSpritesheet(1, "gfx/ui/none.png")
		namestreak:Play("Text")
	end
end

stagesystem:AddCallback(ModCallbacks.MC_POST_UPDATE, stagesystem.Update)
stagesystem:AddCallback(ModCallbacks.MC_POST_RENDER, stagesystem.Render)
stagesystem:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, stagesystem.OnNewLevel)