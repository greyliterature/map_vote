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

    MapVote.Panel.voteArea:SetVote(identifier, mapIndex, voteMult)
end

--@ returns n amount of rows required to fit x number of items under constraint y width
local function CalculateRowCount(squaresize, width, numitems)
    local columncount = math.floor(width / squaresize)
    local rowcount = math.ceil(numitems / columncount)
    return rowcount
end

local Categories = {
    -- the map networking would no longer be needed with this categories table, should only network x number of maps that aren't categorized
    [1] = {
        ["name"] = "MyCoolCategory1",
        ["maps"] = {"gm_c17map", "gm_c17map", "gm_c17map", "gm_c17map", "gm_c17map", "gm_c17map", "gm_c17map", "gm_c17map", "gm_c17map", "gm_c17map",}
    },
    [2] = {
        ["name"] = "MyCoolCategory2",
        ["maps"] = {"fof_city17"}
    },
}

local IconSize = ScrH() * 0.15
local RowGap = ScrH() * 0.005
function MapVote.StartVote(maps, endTime)
    MapVote.EndTime = endTime
    if IsValid(MapVote.Panel) then MapVote.Panel:Remove() end
    local ScreenPanel = vgui.Create("DPanel") -- make this use panel:parenttohud instead or gethudpanel
    MapVote.Panel = ScreenPanel
    ScreenPanel:SetSize(ScrW(), ScrH())
    local VoteFrame = vgui.Create("DPanel", ScreenPanel)
    VoteFrame:SetSize(IconSize * 8 + RowGap * 8, ScrH() * 0.7)
    VoteFrame:SetY(ScrH() * 0.1)
    VoteFrame:CenterHorizontal()
    VoteFrame:MakePopup()
    function VoteFrame.Paint(_, w, h)
        if debugvgui == true then
            surface.SetDrawColor(mapvote_colortable.color_blue)
            surface.DrawRect(0, 0, w, h)
        end
    end

    local TopDropDock = ScrH() * 0.01
    local SixtyFour = ScrH() * 0.059259999 -- basically 64
    for _, tbl in ipairs(Categories) do
        local DropDown = vgui.Create("SDropDown", VoteFrame)
        DropDown:Dock(TOP)
        DropDown:SetWide(VoteFrame:GetWide())
        DropDown:DockMargin(0, 0, 0, TopDropDock)
        DropDown:SetTall(SixtyFour * 0.4)
        --DropDown:DockPadding(0, DropDown:GetTall(), 0, 0)
        local RowCount = CalculateRowCount(IconSize + RowGap, DropDown:GetWide(), #tbl.maps)
        local ExpandedSize = RowCount * IconSize + (RowCount - 1) * RowGap
        DropDown:SetExpandedSize(ExpandedSize)
        local Grid = nil
        function DropDown:FullyExpandedHook()
            Grid = vgui.Create("SGrid", DropDown)
            Grid:SetOverallAlignment(SGRID_ALIGN_LEFT)
            --Grid:DockMargin(0, DropDown:GetMinimizedSize(), 0, 0)
            Grid:SetWide(DropDown:GetWide())
            Grid:Dock(TOP) --0, 0 + DropDown:GetMinimizedSize())
            --Grid:Hide()
            function Grid.Paint(_, w, h)
                if debugvgui == true then
                    surface.SetDrawColor(mapvote_colortable.color_red)
                    surface.DrawRect(0, 0, w, h)
                end
            end

            for i = 1, #tbl.maps do
                local SpacerPanel = vgui.Create("DPanel", row)
                function SpacerPanel.Paint(_, w, h)
                    if debugvgui == true then
                        surface.SetDrawColor(mapvote_colortable.color_yellow)
                        surface.DrawRect(0, 0, w, h)
                    end
                end

                SpacerPanel:SetWide(RowGap)
                local VoteIcon = vgui.Create("mapvote_SVoteIcon", row) -- requires parent only because of autorefresh being annoying
                VoteIcon:SetMap(tbl.maps[i])
                VoteIcon:DownloadMap()
                VoteIcon:SetSize(IconSize, IconSize)
                Grid:SetRowHeight(IconSize)
                Grid:AddItem(VoteIcon)
                Grid:AddItem(SpacerPanel)
            end

            MapVote.ThumbDownloader:RequestWorkshopIDs()
            Grid:Show()
        end

        function DropDown:FullyMinimizedHook()
            if IsValid(Grid) then
                print("Removed")
                Grid:Remove()
            end
        end
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
