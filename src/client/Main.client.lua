print("[Client] Booting NecroSnake client")

local UnitBillboardService = require(script.Parent.Services.UnitBillboardService)
UnitBillboardService.start()

local UnitHighlightService = require(script.Parent.Services.UnitHighlightService)
UnitHighlightService.start()

print("[Client] Client boot complete")