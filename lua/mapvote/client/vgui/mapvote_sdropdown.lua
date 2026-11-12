-- SDropDown
local PANEL = {}
local fontCreated = {}
local function iconFont(size)
    -- no smaller  than 10
    size = math.max(size, 10)
    if fontCreated["MapVote_MapIcon" .. size] then return "MapVote_MapIcon" .. size end
    local name = "MapVote_MapIcon" .. size
    surface.CreateFont(name, {
        font = "Roboto",
        size = size,
        weight = 600,
        antialias = true,
        shadow = true,
        outline = true,
    })

    fontCreated[name] = true
    return name
end

local TriangHeight = ScrH() * 0.007
local TriangLength = ScrW() * 0.004
local offset = 0
function PANEL:Init()
    --[[
                figure out what selfs to delete here later, copy pasted from when work on mapvote version
            --]]
    self.avatarSize = 50
    self.maps = {}
    self.rows = {}
    self.votes = {}
    self.avatarIconPadding = 1
    self.FullyMinimized = true
    self.Minimizing = false
    --self.MinimizedSize = self:GetTall() + ExponentialOffset
    self.Expanding = false
    self.FullyExpanded = false
    self.ExpandedSize = 400 -- size to hold all maps
    self.CategoryTitle = "%PLACEHOLDER_TITLE%"
    self:SetMouseInputEnabled(true)
    --self.MinimizedSize = self:GetTall()
    self.DropDownTriangleTable = {{}, {}, {}}
end

function PANEL:GetMinimizedSize() -- the size of the top dropdown "frame" (not really a frame but looks like one)
    return self.MinimizedSize
end

local ExponentialOffset = 3 -- counter approaching
function PANEL:SetExpandedSize(tallness)
    self.ExpandedSize = tallness + ExponentialOffset
end

function PANEL:PerformLayout(width, tallness)
    self.DropDownTriangleTable[1].x = width * 0.98 + offset
    self.DropDownTriangleTable[2].x = (width - TriangLength) * 0.98 + offset
    self.DropDownTriangleTable[3].x = (width + TriangLength) * 0.98 + offset
    self.DropDownTriangleTable[1].y = (self.MinimizedSize + ExponentialOffset) * 0.5 + TriangHeight * 0.5 + offset
    self.DropDownTriangleTable[2].y = (self.MinimizedSize + ExponentialOffset) * 0.5 - TriangHeight * 0.5 + offset
    self.DropDownTriangleTable[3].y = (self.MinimizedSize + ExponentialOffset) * 0.5 - TriangHeight * 0.5 + offset
end

function PANEL:GetExpandedSize()
    return self.ExpandedSize
end

function PANEL:SetCategory(Category)
    self.Category = category
end

function PANEL:GetCategory()
    return self.Category()
end

local function ExpDecay(a, b, decay, dt) -- from styledstrike glide github, cant get link because writing by hand
    -- REPLACE THIS LATER exponentials are annoying to deal with
    return b + (a - b) * math.exp(-decay * dt)
end

function PANEL:Think()
    if not self.FirstThink then -- doing this in PANEL:Init() messes up for some reason
        self.FirstThink = true
        PANEL.oldSetTall = vgui.GetControlTable("DPanel")["SetTall"]
        self.MinimizedSize = self:GetTall() - ExponentialOffset
        self:DockPadding(0, self.MinimizedSize, 0, 0)
        self:SetExpandedSize(self.MinimizedSize + self:GetExpandedSize() - ExponentialOffset) -- this leaves some space on the bottom but for now we wont care
        function PANEL:SetTall(tallness, dynamiccall)
            self.oldSetTall(self, tallness)
            if not dynamiccall then -- only set minimizedsize for non dynamic settalls
                self.MinimizedSize = tallness - ExponentialOffset
            end
        end
    end

    if self.Expanding == true then
        if self:GetTall() >= self.ExpandedSize - ExponentialOffset then
            self.Expanding = false
            self:FullyExpandedHook() -- a hook
            self.FullyExpanded = true
        end

        self:SetTall(ExpDecay(self:GetTall(), self.ExpandedSize, 15, FrameTime()), true)
    end

    if self.Minimizing == true then
        self.FullyExpanded = false
        self.Expanding = false
        if self:GetTall() <= self.MinimizedSize + ExponentialOffset then
            self.Minimizing = false
            self.FullyMinimized = true
            self:FullyMinimizedHook()
        end

        self:SetTall(ExpDecay(self:GetTall(), self.MinimizedSize, 7, FrameTime()), true)
    end
end

function PANEL:SetCategoryTitle(title)
    self.CategoryTitle = title
end

function PANEL:GetCategoryTitle(title)
    return self.CategoryTitle
end

function PANEL:Paint(w, h)
    surface.SetDrawColor(color_black)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(color_white)
    draw.SimpleText(self:GetCategoryTitle(), iconFont(23), w * 0.01, (self.MinimizedSize + ExponentialOffset) * 0.5, MapVote.style.colorTextPrimary, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    if not self.DropDownTriangleTable[1].x then -- simple check
        return
    end

    draw.NoTexture()
    surface.DrawPoly(self.DropDownTriangleTable)
end

function PANEL:Expand()
    self.Minimizing = false
    self.Expanding = not self.Expanding
    if self.Expanding == false then --
        self.Minimizing = true
    end

    self.ExpandStartTime = CurTime()
end

function PANEL:Minimize()
    self.Expanding = false
    self.Minimizing = true
    self.ExpandStartTime = CurTime()
end

function PANEL:OnMousePressed(keyCode)
    if keyCode == MOUSE_LEFT then
        if not self.FullyExpanded then
            print("1")
            self:Expand()
        elseif self.FullyExpanded then
            print("2")
            self:Minimize()
        end
    end
end

function PANEL:removeVote(oldVote, removePanel)
    if removePanel == nil then removePanel = true end
    local mapData = self.maps[oldVote.mapname]
    -- Find index in votes for the old map, then reposition all icons after it
    local indexToRemove = nil
    for i, voter in ipairs(mapData.voters) do
        if voter == oldVote.panel then
            indexToRemove = i
            break
        end
    end

    if indexToRemove then
        table.remove(mapData.voters, indexToRemove)
    else
        ErrorNoHalt("No index to remove??")
        return
    end

    for i = indexToRemove, #mapData.voters do
        local voter = mapData.voters[i]
        local newX, newY, willOverflow = self:CalculateDesiredAvatarIconPosition(mapData, i)
        voter:SetVisible(true)
        voter.inAnimation = true
        voter:MoveTo(newX, newY, 0.3, nil, 1, function(_, pnl)
            pnl:SetVisible(not willOverflow)
            pnl.inAnimation = false
        end)
    end

    if removePanel then oldVote.panel:Remove() end
    self:calculateIconPercents()
end

function PANEL:RemoveVote(identifier)
    local vote = self.votes[identifier]
    if not vote then return end
    self:removeVote(vote)
    self.votes[identifier] = nil
end

---@param identifier string|Player
---@return Player|nil
---@private
function PANEL:GetPlayerFromIdentifier(identifier)
    if type(identifier) == "string" then
        return player.GetBySteamID64(identifier)
    elseif type(identifier) == "Player" then
        return identifier
    end
    return nil
end

function PANEL:CreateVoterPanel(identifier, voteMult)
    local ply = self:GetPlayerFromIdentifier(identifier)
    local iconContainer = vgui.Create("Panel", self)
    local icon = vgui.Create("AvatarImage", iconContainer) --[[@as AvatarImage]]
    icon:SetSize(self.avatarSize, self.avatarSize)
    icon:SetZPos(1000)
    iconContainer.ply = ply
    icon:SetPlayer(ply, self.avatarSize)
    iconContainer:SetSize(self.avatarSize + 2, self.avatarSize + 2)
    icon:SetPos(2, 2)
    iconContainer:SetMouseInputEnabled(false)
    icon:SetAlpha(200)
    if voteMult > 1 then
        local fontName = CreateMultFont(self.avatarSize)
        icon.PaintOver = function() draw.SimpleTextOutlined(voteMult .. "x", fontName, 2, 2, MapVote.style.colorTextPrimary, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, MapVote.style.colorPrimaryBG) end
    end
    return iconContainer
end

local function GetTrueMapIndex(mapname)
    print("GetTrueMapIndex() is inefficient, make it better later")
    for mapIndex, mapName in ipairs(MapVote.GetMapList()) do
        if mapName == mapname then return mapIndex end
    end
end

---@param maps string[]
function PANEL:SetMaps(maps)
    self.maps = {}
    for i, map in ipairs(maps) do
        self.maps[map] = {
            voters = {}, -- useless table
        }
    end
end

function PANEL:calculateIconPercents()
    local totalVotes = 0
    local mapVotes = {}
    for _, vote in pairs(self.votes) do
        totalVotes = totalVotes + vote.voteMult
        mapVotes[vote.mapname] = (mapVotes[vote.mapname] or 0) + vote.voteMult
    end

    if totalVotes == 0 then return end
    for mapname, mapData in ipairs(self.maps) do
        local votes = mapVotes[mapname] or 0
        local percentage = (votes / totalVotes) * 100
        ---@diagnostic disable-next-line: undefined-field
        mapData.panel:SetPercent(percentage)
    end
end

---@param mapPanel Panel
---@return number, number
---@private
function PANEL:GetPositionRelativeToSelf(mapPanel)
    local screenX, screenY = mapPanel:LocalToScreen(0, 0)
    local x, y = self:ScreenToLocal(screenX, screenY)
    return x, y
end

---@param mapData VoteAreaMap
---@param index number|nil
---@return number, number, boolean
function PANEL:CalculateDesiredAvatarIconPosition(mapData, index)
    if not index then index = #mapData.voters end
    index = index - 1
    local avatarIconPadding = self.avatarIconPadding
    local avatarTotalSize = self.avatarSize + avatarIconPadding * 2
    local mapIcon = mapData.panel
    PrintTable(self.maps)
    print("HIIIddddddddddddddddddddd")
    local maxColumnCount = math.floor(mapIcon:GetWide() / avatarTotalSize)
    local maxRowCount = math.floor((mapIcon:GetTall() - 20) / avatarTotalSize)
    local column = index % maxColumnCount
    local row = math.floor(index / maxColumnCount)
    local x = column * avatarTotalSize + avatarIconPadding
    local y = row * avatarTotalSize + avatarIconPadding
    local rootPosX, rootPosY = self:GetPositionRelativeToSelf(mapIcon)
    if MapVote.style.bottomUpIconFilling then
        rootPosX = rootPosX + (mapIcon:GetWide() - avatarTotalSize - 2 * avatarIconPadding)
        rootPosY = rootPosY + (mapIcon:GetTall() - avatarTotalSize - 2 * avatarIconPadding)
        return rootPosX - x, rootPosY - y, row >= maxRowCount
    end
    return rootPosX + x, rootPosY + y, row >= maxRowCount
end

function PANEL:SetVote(identifier, mapIndex, voteMult)
    local mapname = MapVote.GetMapList()[mapIndex]
    local mapData = self.maps[mapname]
    if not mapData then
        PrintTable(self.maps)
        error("Invalid map index " .. mapname)
        return
    end

    local oldVote = self.votes[identifier]
    local panel
    if oldVote then
        if oldVote.mapname == mapname then return end
        if oldVote.voteMult ~= voteMult then
            self:removeVote(oldVote, true)
            panel = self:CreateVoterPanel(identifier, voteMult)
        else
            self:removeVote(oldVote, false)
            panel = oldVote.panel
        end
    else
        panel = self:CreateVoterPanel(identifier, voteMult)
    end

    table.insert(mapData.voters, panel)
    self.votes[identifier] = {
        identifier = identifier,
        mapname = mapname,
        panel = panel,
        voteMult = voteMult
    }

    local newX, newY, willOverflow = self:CalculateDesiredAvatarIconPosition(mapData)
    panel:SetVisible(true)
    panel.inAnimation = true
    panel:MoveTo(newX, newY, 0.3, nil, 1, function(_, pnl)
        pnl:SetVisible(not willOverflow)
        pnl.inAnimation = false
    end)

    self:calculateIconPercents()
end

--[[
    -- override this
    function PANEL:DoClick()
    end
--]]
vgui.Register("SDropDown", PANEL, "DPanel")
