local Scene = require("client.src.scenes.Scene")
local class = require("common.lib.class")
local ui = require("client.src.ui")
local input = require("client.src.inputManager")
local tableUtils = require("common.lib.tableUtils")

-- Scene for selecting a sub-character variant from a bundle character
---@class SubCharacterSelectScene : Scene
---@field bundleCharacter Character the bundle character whose sub-variants are shown
---@field player Player the player making the selection
---@field battleRoom BattleRoom the current battle room
---@field onComplete function? optional callback when selection is complete
---@field backgroundImg table the background image
---@field subCharacters Character[] the list of sub-characters to display
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

function SubCharacterSelectScene:draw()
  self.backgroundImg:draw()
  self.uiRoot:draw()
end

return SubCharacterSelectScene
