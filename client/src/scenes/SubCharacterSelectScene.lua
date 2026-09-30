local Scene = require("client.src.scenes.Scene")
local class = require("common.lib.class")
local ui = require("client.src.ui")
local input = require("client.src.inputManager")
local tableUtils = require("common.lib.tableUtils")
local consts = require("common.engine.consts")
local GraphicsUtil = require("client.src.graphics.graphics_util")
local Character = require("client.src.mods.Character")

-- Scene for selecting a sub-character variant from a bundle character
---@class SubCharacterSelectScene : Scene
---@field bundleCharacter Character the bundle character whose sub-variants are shown
---@field player Player the player making the selection
---@field battleRoom BattleRoom the current battle room
---@field onComplete function? optional callback when selection is complete
---@field backgroundImg table the background image
---@field subCharacters Character[] the list of sub-characters to display
---@field portraitCache table<string, {portrait: love.Texture?, portrait2: love.Texture?}> cached portrait textures per sub-character id
---@field currentPortrait love.Texture? portrait currently shown as the side preview
---@field currentPortraitMirror boolean whether the current portrait is drawn mirrored (player 2 without portrait2)
local SubCharacterSelectScene = class(
---@param self SubCharacterSelectScene
function(self, sceneParams)
  self.keepMusic = true
  self.bundleCharacter = sceneParams.bundleCharacter
  self.player = sceneParams.player
  self.battleRoom = sceneParams.battleRoom
  self.onComplete = sceneParams.onComplete
  self.backgroundImg = themes[config.theme].images.bg_select_screen
  self.music = "select_screen"
  self.fallbackMusic = "main"
  self:load()
end, Scene)

SubCharacterSelectScene.name = "SubCharacterSelectScene"

function SubCharacterSelectScene:load()
  -- save the player's current cursor so we can restore it when popping
  self.originalCursor = self.player.cursor

  -- gather sub-characters from the bundle
  self.subCharacters = {}
  for _, subId in ipairs(self.bundleCharacter.subIds) do
    if characters[subId] then
      self.subCharacters[#self.subCharacters + 1] = characters[subId]
    end
  end

  -- portrait preview state for the hovered sub-character
  self.portraitCache = {}
  self.currentPortrait = nil
  self.currentPortraitMirror = false

  -- grid layout constants
  local unitSize = 100
  local unitMargin = 8
  local columns = 3
  local rows = math.ceil(#self.subCharacters / columns)

  -- title label
  self.uiRoot:addChild(ui.Label({
    text = "sub_select_title",
    hAlign = "center",
    vAlign = "top",
    y = 30,
  }))

  -- create the grid for sub-character buttons
  self.grid = ui.Grid({
    unitSize = unitSize,
    gridWidth = columns,
    gridHeight = rows,
    unitMargin = unitMargin,
    hAlign = "center",
    vAlign = "center",
  })
  self.uiRoot:addChild(self.grid)

  -- populate the grid with sub-character buttons
  for i, subCharacter in ipairs(self.subCharacters) do
    local col = ((i - 1) % columns) + 1
    local row = math.floor((i - 1) / columns) + 1

    local button = ui.Button({
      hFill = true,
      vFill = true,
      backgroundColor = {0.2, 0.2, 0.2, 0.7},
      outlineColor = {0.5, 0.5, 0.5, 0.7},
    })

    button.characterId = subCharacter.id

    -- character icon image
    local iconContainer = ui.ImageContainer({
      image = subCharacter.images.icon,
      hAlign = "center",
      vAlign = "center",
      hFill = true,
      vFill = true,
    })
    button:addChild(iconContainer)

    -- character display name label below the icon
    local nameLabel = ui.Label({
      text = subCharacter.display_name,
      translate = false,
      hAlign = "center",
      vAlign = "bottom",
      y = -4,
    })
    button:addChild(nameLabel)

    -- click handler for this sub-character
    button.onClick = function(selfElement, inputSource, holdTime)
      local player
      if inputSource and inputSource.player then
        player = inputSource.player
      else
        player = self.player
      end
      player:setCharacter(selfElement.characterId)
      player.cursor = self.originalCursor
      characters[selfElement.characterId]:playSelectionSfx()
      GAME.theme:playValidationSfx()
      GAME.navigationStack:pop()
      if self.onComplete then
        self.onComplete(selfElement.characterId)
      end
    end
    -- also set onSelect so the grid cursor can navigate to and activate this button
    button.onSelect = button.onClick

    self.grid:createElementAt(col, row, 1, 1, "subCharacter", button, nil, true)
  end

  -- back button
  self.backButton = ui.TextButton({
    label = ui.Label({text = "back"}),
    hAlign = "center",
    vAlign = "bottom",
    y = -30,
    onClick = function()
      self:goBack()
    end,
  })
  self.uiRoot:addChild(self.backButton)

  -- create grid cursor for keyboard/gamepad navigation
  local playerIndex = tableUtils.indexOf(self.battleRoom.players, self.player)
  self.gridCursor = ui.GridCursor({
    grid = self.grid,
    activeArea = {
      x1 = 1,
      y1 = 1,
      x2 = math.min(columns, #self.subCharacters),
      y2 = rows,
    },
    startPosition = {x = 1, y = 1},
    player = self.player,
    translateSubGrids = true,
    frameImages = themes[config.theme]:getGridCursor(playerIndex),
  })

  self.gridCursor.escapeCallback = function()
    self:goBack()
  end

  -- show the portrait of whichever sub-character the cursor is on:
  -- player 1 previews on the left side of the screen, player 2 on the right side
  self.gridCursor.onMove = function(cursor)
    self:updatePortraitPreview()
  end

  -- preload all sub-character portraits so moving the cursor never hitches
  for _, subCharacter in ipairs(self.subCharacters) do
    self:getPortraitImages(subCharacter)
  end
  self:updatePortraitPreview()
end

-- Loads and caches the portrait textures of a sub-character
-- Mirrors Character.graphics_init defaulting: a missing portrait falls back to the default character's art
---@param character Character
---@return {portrait: love.Texture?, portrait2: love.Texture?} portraits
function SubCharacterSelectScene:getPortraitImages(character)
  local cached = self.portraitCache[character.id]
  if cached then
    return cached
  end

  -- characters that are fully loaded already have their (potentially defaulted) portraits in memory
  local portrait = character.images and character.images.portrait
  if not portrait then
    portrait = GraphicsUtil.loadImageFromSupportedExtensions(character.path .. "/portrait")
  end
  if not portrait then
    local defaultCharacter = Character.getDefaultCharacter()
    portrait = defaultCharacter and defaultCharacter.images.portrait
  end

  local portrait2 = character.images and character.images.portrait2
  if not portrait2 then
    portrait2 = GraphicsUtil.loadImageFromSupportedExtensions(character.path .. "/portrait2")
  end

  cached = {portrait = portrait, portrait2 = portrait2}
  self.portraitCache[character.id] = cached
  return cached
end

-- Updates the side portrait preview to the sub-character currently under the grid cursor
function SubCharacterSelectScene:updatePortraitPreview()
  local cursor = self.gridCursor
  if not cursor or not cursor.target then
    return
  end

  local gridElement = cursor:getElementAt(cursor.selectedGridPos.y, cursor.selectedGridPos.x)
  local content = gridElement and gridElement.content
  local character = content and content.characterId and characters[content.characterId]
  if not character then
    return
  end

  local portraits = self:getPortraitImages(character)
  local playerNumber = self.player and self.player.playerNumber or 1
  if playerNumber == 2 and portraits.portrait2 then
    -- player 2 uses the mod's dedicated portrait2 art when it provides one
    self.currentPortrait = portraits.portrait2
    self.currentPortraitMirror = false
  else
    -- player 1 uses portrait.png; on the right side it gets mirrored like Character:drawPortrait does
    self.currentPortrait = portraits.portrait
    self.currentPortraitMirror = playerNumber == 2
  end
end

function SubCharacterSelectScene:goBack()
  -- restore the original cursor from CharacterSelect before popping
  self.player.cursor = self.originalCursor
  GAME.theme:playCancelSfx()
  GAME.navigationStack:pop()
end

function SubCharacterSelectScene:update(dt)
  self.backgroundImg:update(dt)
  self.uiRoot:update(dt)

  -- Forward keyboard/gamepad inputs to the grid cursor
  -- This mirrors the pattern from CharacterSelect:updateSelf(dt)
  if self.player.isLocal and self.player.human then
    if not self.player.inputConfiguration then
      self.gridCursor:receiveInputs(input, dt)
    elseif self.player.settings.inputMethod == "controller" then
      self.gridCursor:receiveInputs(self.player.inputConfiguration, dt)
    end
  end
end

-- Draws the hovered sub-character's portrait.png as background art
-- on the owning player's side of the screen: left for player 1, right for player 2
function SubCharacterSelectScene:drawPortraitPreview()
  if not self.currentPortrait then
    return
  end

  local portraitWidth, portraitHeight = self.currentPortrait:getDimensions()
  if not portraitWidth or portraitWidth <= 0 or portraitHeight <= 0 then
    return
  end

  -- fit the portrait into the free area beside the centered sub-character grid
  local margin = 20
  local gridClearance = 190
  local boxWidth = (consts.CANVAS_WIDTH / 2) - margin * 2 - gridClearance
  local boxHeight = consts.CANVAS_HEIGHT - margin * 2
  local scale = math.min(boxWidth / portraitWidth, boxHeight / portraitHeight)
  local drawWidth = portraitWidth * scale
  local drawHeight = portraitHeight * scale
  local y = (consts.CANVAS_HEIGHT - drawHeight) / 2

  local playerNumber = self.player and self.player.playerNumber or 1
  if playerNumber == 2 then
    -- player 2: right side of the screen
    local x = consts.CANVAS_WIDTH - margin - drawWidth
    if self.currentPortraitMirror then
      -- a negative scale draws to the left of x, so anchor at the right edge of the portrait box
      GraphicsUtil.draw(self.currentPortrait, x + drawWidth, y, 0, -scale, scale)
    else
      GraphicsUtil.draw(self.currentPortrait, x, y, 0, scale, scale)
    end
  else
    -- player 1: left side of the screen
    GraphicsUtil.draw(self.currentPortrait, margin, y, 0, scale, scale)
  end
end

function SubCharacterSelectScene:draw()
  self.backgroundImg:draw()
  self:drawPortraitPreview()
  self.uiRoot:draw()
end

return SubCharacterSelectScene
