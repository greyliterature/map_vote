function MapVote.FinishVote(mapIndex)
    if not IsValid(MapVote.Panel) then return end
    MapVote.Panel:SetMinimized(false)
    MapVote.Panel:SetVisible(true)
    --MapVote.Panel.voteArea:Flash( mapIndex )
end

function MapVote.CancelVote()
    if IsValid(MapVote.Panel) then MapVote.Panel:Remove() end
    hook.Run("MapVote_VoteCancelled")
end

-- the map networking would no longer be needed with this categories table, should only network x number of maps that aren't categorized
local MapToCategory = {
    ["gm_c17map"] = "MyCoolCategory1",
    ["fof_city17"] = "MyCoolCategory2"
}

local DropDowns = {} -- "category" = panel
local Voters = {}
---@param ply Player
---@param mapIndex number
---@param voteMult number
function MapVote.ChangeVote(ply, mapIndex, voteMult)
    if not IsValid(ply) then return end
    if not IsValid(MapVote.Panel) then return end
    ---@type string|Player
    local identifier = ply:SteamID64()
    if ply:IsBot() then
        -- dont use steamid object for bots to allow testing UI locally
        identifier = ply
    end

    --if IsValid(MapVote.Panel.OpenGrid) then MapVote.Panel.OpenGrid:SetVote(identifier, mapIndex, voteMult) end
    local currentMaps = MapVote.GetMapList()
    local mapname = currentMaps[mapIndex]
    local category = MapToCategory[mapname] or "Uncategorized"
    local CategoryDropDown = DropDowns[category]
    print(mapIndex, "HI!")
    local PlayersLastCategoryDropDown = Voters[identifier]
    if IsValid(PlayersLastCategoryDropDown) then PlayersLastCategoryDropDown:RemoveVote(identifier) end
    Voters[identifier] = CategoryDropDown
    CategoryDropDown:SetVote(identifier, mapIndex, voteMult)
end

--@ returns n amount of rows required to fit x number of items under constraint y width
local function CalculateRowCount(squaresize, width, numitems)
    local columncount = math.floor(width / squaresize)
    columncount = math.max(columncount, 1)
    local rowcount = math.ceil(numitems / columncount)
    return rowcount
end

--[[
local Categories = {}
function MapVote.GetCategories()
    Categories = {} -- in case it needs to refresh for whatever reason
    for mapname, category in pairs(MapToCategory) do
        if Categories[category] then continue end
        Categories[category] = {}
    end
    return Categories
end
--]]
function MapVote.GetTrueMapIndex(mapname)
    for mapIndex, mapName in ipairs(MapVote.GetMapList()) do
        if mapName == mapname then return mapIndex end
    end
end

function MapVote.GetMapList()
    return MapVote.currentMaps
end

--[[
local VBarWidth = 64 / 1920 * ScrW()
local minecraft_light_grey = Color(139, 139, 139)
local function DrawScrollBar(w, h)
    surface.SetDrawColor(color_white)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(minecraft_light_grey)
    local ScrollMargin = h * 0.01
    surface.DrawRect(ScrollMargin, ScrollMargin, w - ScrollMargin * 2, h - ScrollMargin * 2)
end
--]]
-- col
local color_cod_light_black = Color(35, 35, 35, 254)
local color_cod_black = Color(0, 0, 0, 254)
--
local SixtyFour = ScrH() * 0.059259999 -- basically 64
local IconSize = ScrH() * 0.15
local RowGap = ScrH() * 0.005
local HeaderSize = ScrH() * 0.05
function MapVote.StartVote(maps, endTime)
    MapVote.EndTime = endTime
    if IsValid(MapVote.Panel) then MapVote.Panel:Remove() end
    local OuterPanel = vgui.Create("DPanel")
    -- always make outer panel hold 6 icons + 2 rowgaps to account for horiz sgrid padding 
    -- and 2 headers
    OuterPanel:SetSize(IconSize * 6 + RowGap * 5 + RowGap * 2, ScrH() * 0.5 + HeaderSize * 2)
    OuterPanel:Center()
    function OuterPanel.Paint(_, _, _)
    end

    OuterPanel:MakePopup()
    local TopHeader = vgui.Create("DPanel", OuterPanel)
    TopHeader:Dock(TOP)
    TopHeader:SetTall(HeaderSize)
    function TopHeader.Paint(_, w, h)
        surface.SetDrawColor(color_cod_black)
        surface.DrawRect(0, 0, w, h)
    end

    MapVote.Panel = OuterPanel
    local ScreenPanel = vgui.Create("DScrollPanel", OuterPanel)
    --ScreenPanel:MakePopup()
    ScreenPanel:Dock(TOP)
    ScreenPanel:SetWide(OuterPanel:GetWide())
    ScreenPanel:SetTall(ScrH() * 0.5)
    -- SCREENPANELS HEIGHT IS WRONG. there is a large margin below the bottom dropdown, which is ugly
    local VBar = ScreenPanel:GetVBar()
    function VBar.Paint(_, _, _)
    end

    function VBar.btnGrip.Paint(_, w, h)
    end

    function VBar.btnDown.Paint(_, w, h)
    end

    function VBar.btnUp.Paint(_, w, h)
    end

    VBar:SetWide(0) -- fixes annoying docking issues
    local VoteFrame = vgui.Create("DPanel", ScreenPanel)
    VoteFrame:SetSize(ScreenPanel:GetWide(), ScrH() * 0.7)
    VoteFrame:SetY(0, 0)
    VoteFrame:CenterHorizontal()
    VoteFrame:Dock(FILL)
    --VoteFrame:MakePopup()
    function VoteFrame.Paint(_, w, h)
        if debugvgui == true then
            surface.SetDrawColor(mapvote_colortable.color_blue)
            surface.DrawRect(0, 0, w, h)
        end

        surface.SetDrawColor(color_cod_light_black)
        surface.DrawRect(0, 0, w, h)
    end

    local TopDropDock = ScrH() * 0.01
    local Categories = {}
    for mapIndex, mapName in ipairs(maps) do
        local category = MapToCategory[mapName] or "Uncategorized"
        Categories[category] = Categories[category] or {}
        Categories[category][#Categories[category] + 1] = mapName
    end

    DropDowns = {}
    for mapIndex, mapName in ipairs(maps) do
        local category = MapToCategory[mapName] or "Uncategorized"
        if not DropDowns[category] then
            local DropDown = vgui.Create("SDropDown", VoteFrame)
            DropDown:Dock(TOP)
            DropDown:SetWide(VoteFrame:GetWide())
            DropDown:DockMargin(0, 0, 0, TopDropDock)
            DropDown:SetTall(SixtyFour * 0.5)
            DropDown:SetCategoryTitle(category)
            PrintTable(Categories[category])
            print("HII")
            DropDown:SetMaps(Categories[category])
            local RowCount = CalculateRowCount(IconSize + RowGap, DropDown:GetWide(), table.Count(Categories[category]))
            local ExpandedSize = RowCount * IconSize + (RowCount - 1) * RowGap + RowGap
            DropDown:SetExpandedSize(ExpandedSize)
            DropDowns[category] = DropDown
            function DropDown:FullyExpandedHook()
                if IsValid(self.Grid) then return end
                local Grid = vgui.Create("SGrid", DropDown)
                Grid:SetOverallAlignment(SGRID_ALIGN_LEFT)
                Grid:DockMargin(RowGap, 0, 0, 0)
                Grid:SetWide(DropDown:GetWide())
                Grid:Dock(TOP)
                self.Grid = Grid
                function Grid.Paint(_, w, h)
                    if debugvgui == true then
                        surface.SetDrawColor(mapvote_colortable.color_red)
                        surface.DrawRect(0, 0, w, h)
                    end
                end

                for mapindex, mapname in ipairs(Categories[category]) do
                    print("HI", mapindex, mapname)
                    if (MapToCategory[mapname] or "Uncategorized") ~= category then -- this is inefficient but it works, whatever
                        continue
                    end

                    print(mapname, "HAAHAH")
                    local SpacerPanel = vgui.Create("DPanel", row)
                    function SpacerPanel.Paint(_, w, h)
                        if debugvgui == true then
                            surface.SetDrawColor(mapvote_colortable.color_yellow)
                            surface.DrawRect(0, 0, w, h)
                        end
                    end

                    SpacerPanel:SetWide(RowGap)
                    local VoteIcon = vgui.Create("MapVote_MapIcon", Grid) -- requires parent only because of autorefresh being annoying
                    VoteIcon:SetMap(mapname)
                    function VoteIcon.DoClick(_)
                        MapVote.Net.changeVote(mapIndex)
                    end

                    self.maps[mapname].panel = VoteIcon
                    print(VoteIcon, "hiya")
                    --VoteIcon:DownloadMap()
                    VoteIcon:SetSize(IconSize, IconSize)
                    Grid:SetRowHeight(IconSize)
                    Grid:AddItem(VoteIcon)
                    Grid:AddItem(SpacerPanel)
                end

                print("requesting workshop")
                MapVote.ThumbDownloader:RequestWorkshopIDs()
                Grid:Show()
            end

            function DropDown:FullyMinimizedHook()
                if IsValid(self.Grid) then
                    print("Removed")
                    self.Grid:Remove()
                end
            end
            --[[--]]
        end
    end

    local BottomHeader = vgui.Create("DPanel", OuterPanel)
    BottomHeader:Dock(TOP)
    BottomHeader:SetTall(HeaderSize)
    function BottomHeader.Paint(_, w, h)
        surface.SetDrawColor(color_cod_black)
        surface.DrawRect(0, 0, w, h)
    end

    hook.Run("MapVote_VoteStarted")
    hook.Run("MapVote_VotePanelOpened")
end

hook.Add("InitPostEntity", "MapVote_RequestState", function() timer.Simple(5, function() MapVote.Net.requestState() end) end)
gameevent.Listen("player_disconnect")
hook.Add("player_disconnect", "MapVote_RemoveVote", function(data)
    if not IsValid(MapVote.Panel) then return end
    if data.networkid == "BOT" then
        MapVote.Panel.voteArea:RemoveInvalidVotes()
    else
        MapVote.Panel.voteArea:RemoveVote(util.SteamIDTo64(data.networkid))
    end
end)
