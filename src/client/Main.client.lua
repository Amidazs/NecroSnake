print("[Client] Booting NecroSnake client")

local UnitBillboardService = require(script.Parent.Services.UnitBillboardService)
local billboardService = UnitBillboardService.new()
billboardService:init()

local UnitHighlightService = require(script.Parent.Services.UnitHighlightService)
local highlightService = UnitHighlightService.new()
highlightService:init()

print("[Client] Client boot complete")
