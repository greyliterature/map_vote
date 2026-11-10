SGRID_ALIGN_LEFT = 0
SGRID_ALIGN_CENTER = 1
SGRID_ALIGN_RIGHT = 2
local PANEL = {
    OverallAlignment = SGRID_ALIGN_CENTER,
    RowAlignments = {},
    Items = {},
    Rows = {},
    RowGap = ScrH() * 0.005,
    RowGapColor = Color(0, 0, 0, 0), -- null
    Justify = 0,
    ColumnCount = 0
}

function PANEL:Init()
    self.RowHeight = nil -- self:GetTall()
    self.Items = {}
    self.Rows = {}
    self.RowAlignments = {}
    self.RowHeight = self:GetTall()
end

function PANEL:SetRowAlignment(rownumber, alignment)
    --if not self.Rows[rownumber] then return end -- don't think this return matters, operator should know what they're doing
    self.RowAlignments[rownumber] = alignment
end

function PANEL:SetJustify(justify) -- alignment margins, you can get the same effect with just moving the panel
    self.Justify = justify
end

function PANEL:SetOverallAlignment(alignment)
    self.OverallAlignment = alignment
    self:AlignItems()
end

function PANEL:DestroyRows() -- internal, dont touch this
    for _, tbl in ipairs(self.Items) do
        if IsValid(tbl[1]) then tbl[1]:SetParent(self) end
    end

    for i = 1, #self.Rows do
        if IsValid(self.Rows[i]) then self.Rows[i]:Remove() end
    end

    self.Rows = {}
end

function PANEL:SetColumnCount(columncount)
    if columncount == 1 then -- 
        self.GapToNext = 0
    end

    self.ColumnCount = columncount
end

function PANEL:GetShape() -- internal, doubt you're going to need or want this
    local TotalRowLength = 0
    local MaxColumnsPerRow = self.ColumnCount or 0
    local WidestGridElement = 0
    for _, tbl in ipairs(self.Items) do
        local width = tbl[2]
        WidestGridElement = math.max(WidestGridElement, width)
        TotalRowLength = TotalRowLength + width
        if TotalRowLength < self:GetWide() and self.ColumnCount == 0 then --
            MaxColumnsPerRow = MaxColumnsPerRow + 1
        end
    end

    if WidestGridElement > self:GetWide() and not self.ErroredAlready then
        ErrorNoHaltWithStack("The SGrid is too thin to hold any of its elements, make it wider" .. "Widest element: " .. WidestGridElement .. " " .. "self: " .. self:GetWide())
        self.ErroredAlready = true
    end

    if MaxColumnsPerRow == 0 then MaxColumnsPerRow = 1 end
    local RowsNeeded = math.floor(#self.Items / MaxColumnsPerRow) + 1
    return TotalRowLength, MaxColumnsPerRow, RowsNeeded
end

function PANEL:CreateRows()
    local _, MaxColumnsPerRow, _ = self:GetShape()
    self.MaxColumnsPerRow = MaxColumnsPerRow
    local RowsNeeded = math.floor(#self.Items / MaxColumnsPerRow) + 1 -- how many times can we fit items with maxcolumn amountsperrow
    local RowHeight = self.RowHeight
    local ActualItemIndex = 1
    for i = 1, RowsNeeded do -- divide into rows at each overflow
        local CurrentRowsLength = 0 -- current row's 
        for b = 1, MaxColumnsPerRow do
            if not self.Items[ActualItemIndex] then break end
            local width = self.Items[ActualItemIndex][2]
            CurrentRowsLength = CurrentRowsLength + width
            ActualItemIndex = ActualItemIndex + 1 -- because the for loop resets the index b, but we actually are further along self.Items by this offset
        end

        local Row = vgui.Create("DPanel", self)
        Row:SetWide(CurrentRowsLength)
        Row:SetTall(RowHeight)
        Row:SetBackgroundColor(color_black)
        function Row.Paint()
        end

        --Row:Dock(TOP)
        Row:SetY((i - 1) * RowHeight + self.RowGap * (i - 1))
        local Alignment = self.RowAlignments[i] or self.OverallAlignment
        local AlignmentOffset = (Alignment == SGRID_ALIGN_LEFT and 0 + self.Justify) or (Alignment == SGRID_ALIGN_RIGHT and (self:GetWide() - CurrentRowsLength) - self.Justify) or (Alignment == SGRID_ALIGN_CENTER and ((self:GetWide() - CurrentRowsLength) * 0.5))
        Row:SetX(AlignmentOffset)
        self.Rows[i] = Row
    end

    self:SetTall(RowsNeeded * RowHeight + (RowsNeeded - 1) * self.RowGap)
end

function PANEL:AlignItems(alignment)
    self:DestroyRows()
    self:CreateRows()
    --local RowNumber = 1
    local CurrentLength = 0
    local MaxColumnsPerRow = self.MaxColumnsPerRow
    for i, tbl in ipairs(self.Items) do
        local panel = tbl[1]
        if not IsValid(panel) then -- this should table.remove but im lazy right now
            continue
        end

        local width = tbl[2]
        CurrentLength = CurrentLength + width
        local RowNumber = math.ceil(i / MaxColumnsPerRow) -- pretty much reverse of RowsNeeded math.floor(#self.Items / MaxColumnsPerRow) + 1
        local Row = self.Rows[RowNumber]
        panel:SetParent(Row)
        panel:Dock(LEFT)
        panel:SetWide(width)
    end
end

function PANEL:AddItem(PanelObject)
    --PanelObject:Dock(LEFT)
    --PanelObject:SetWide(10)
    local width = PanelObject:GetWide()
    self.Items[#self.Items + 1] = {
        PanelObject, -- make this not a table or add to it later
        width,
    }

    self:AlignItems()
end

function PANEL:SetRowHeight(height)
    self.RowHeight = height
    if #self.Items > 0 then self:AlignItems() end
end

function PANEL:GetRowHeight(height)
    return self.RowHeight
end

function PANEL:SetRowGap(gap)
    self.RowGap = gap
end

--[[
        -- do not feel like implementing this!
        -- if you want to implement this, you will have to place a SpacerPanel after 
        -- each row's SetY, account for it, etc. Pretty simple,
        -- but I see no need to waste my time on it right now 
        function PANEL:SetRowGapColor(col)
            self.RowGapColor = col
        end
        --]]
function PANEL:GetRowGap()
    return self.RowGap
end

function PANEL:RemoveItem(PanelObject)
    for i = #self.Items, 1, -1 do
        local tbl = self.Items[i]
        local panel = tbl[1]
        if panel == PanelObject then
            table.remove(self.Items, i)
            panel:Remove()
            break
        end
    end

    self:AlignItems()
end

function PANEL:Alignment(Alignment)
end

vgui.Register("SGrid", PANEL, "DPanel")
