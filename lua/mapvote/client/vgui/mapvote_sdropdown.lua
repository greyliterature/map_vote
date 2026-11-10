-- SDropDown
local PANEL = {}
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

function PANEL:Paint(w, h)
    surface.SetDrawColor(color_black)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(color_white)
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

--[[
        -- override this
        function PANEL:DoClick()
        end
        --]]
vgui.Register("SDropDown", PANEL, "DPanel")
