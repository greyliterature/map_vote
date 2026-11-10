-- SMapvoteIcon
local MapMaterials = {}
-- SVoteIcon
local PANEL = {}
function PANEL:Init()
    self.Map = nil
    self.WSID = nil -- is this important to store?
    self.MapMaterial = nil
    self:SetMouseInputEnabled(true)
    self.Votes = {}
    self.Grid = vgui.Create("SGrid", self)
    self.Grid:Dock(FILL)
    self.Grid:SetOverallAlignment(SGRID_ALIGN_RIGHT)
    function self.Grid.Paint(_, w, h)
        if debugvgui == true then
            surface.SetDrawColor(mapvote_colortable.color_transparentishpurple)
            surface.DrawRect(0, 0, w, h)
        end
    end

    function self.Grid.OnMousePressed(_, keyCode)
        self:OnMousePressed(keyCode)
    end
end

function PANEL:IsMapAlreadyRegistered(mapname) -- this is a helper function that doesn't really belong on the object, but i dont know wheree else to puts it
    return MapMaterials[mapname]
end

local MapToPanel = {}
function PANEL:SetMap(mapname)
    MapToPanel[mapname] = self -- this means that it conflicts much more easily, 
    -- but it definitely should be expected behavior that having two panels of
    -- the same map will cause issues.
    self.Map = mapname
end

function PANEL:GetMapName()
    return self.Map
end

function PANEL:DownloadMap()
    local mapname = self:GetMapName()
    --[[
    MapVote.ThumbDownloader:QueueDownload(mapname, function(material)
        MapVote.TaskManager.AddFunc(function()
            ---@diagnostic disable-next-line: missing-parameter
            local mat = Material(material)
            self.MapMaterial = mat
            print(mat, "HII GOT IT")
        end)
    end)
    --]]
    MapVote.ThumbDownloader:QueueDownload(mapname, function(material)
        MapVote.TaskManager.AddFunc(function()
            self.MapMaterial = material
            return
        end)
    end)
    --MapVote.ThumbDownloader:RequestSingleWorkshopID(mapname)
end

local ERROR_DOWNLOADING_MAT = Material("maps/thumb/noicon.png")
function PANEL:Paint(w, h)
    surface.SetDrawColor(color_white)
    surface.SetMaterial(self.MapMaterial or ERROR_DOWNLOADING_MAT)
    surface.DrawTexturedRect(0, 0, w, h)
    if debugvgui == true then -- for showing if the bottom renders fully  
        surface.SetDrawColor(ColorRand())
        surface.DrawOutlinedRect(0, 0, w, h, 1)
    end
end

local PlayerPanelVotes = {}
local PlayerAvatars = {}
--@ forced arg is used by the net.receive callback to force past the localplayer return
function PANEL:RemoveVoteForMap(ply, forced)
    if not self.Votes[ply] then return end
    if ply == LocalPlayer() then
        net.Start("rv_mapvote_vote_map")
        net.WriteBool(true) -- bool of whether or not we're removing the vote
        net.WriteString(self:GetMapName())
        net.SendToServer()
    end

    self.Votes[ply] = nil
    self.Grid:RemoveItem(PlayerAvatars[ply])
    PlayerPanelVotes[ply] = nil
    PlayerAvatars[ply] = nil
end

local LastVoteTime = 0
--@ forced arg is used by the net.receive callback to force past the localplayer return
function PANEL:VoteForMap(ply, forced)
    if PlayerPanelVotes[ply] == self then return end
    if IsValid(PlayerPanelVotes[ply]) then --
        PlayerPanelVotes[ply]:RemoveVoteForMap(ply)
    end

    if ply == LocalPlayer() and not forced then
        if LastVoteTime + MapVoteRateLimit > CurTime() then -- this is just for prediction, and is also done serverside 
            return
        end

        LastVoteTime = CurTime()
        net.Start("rv_mapvote_vote_map")
        net.WriteBool(false) -- bool of whether or not we're removing the vote
        net.WriteString(self:GetMapName())
        net.SendToServer()
        return
    end

    PlayerPanelVotes[ply] = self
    self.Votes[ply] = true
    print(ply, "voted for ", self)
    --self:AddToVoterPanel(ply)
    local IconSize = self:GetTall() * 0.2 -- this shouldnt be static, but ignorable for now
    local Avatar = vgui.Create("AvatarImage", self.Grid)
    Avatar:SetPlayer(ply, 184)
    Avatar:SetWide(IconSize)
    self.Grid:AddItem(Avatar)
    self.Grid:SetRowHeight(IconSize)
    PlayerAvatars[ply] = Avatar
end

net.Receive("rv_mapvote_votemap_announcement", function(_, _)
    print("REC HI")
    local RemoveVote = net.ReadBool()
    local MapName = net.ReadString()
    local ply = net.ReadPlayer()
    local MapPanel = MapToPanel[MapName]
    if not IsValid(MapPanel) then return end
    if RemoveVote == false then
        print("vote")
        MapPanel:VoteForMap(ply, true)
    else
        print("remove")
        MapPanel:RemoveVoteForMap(ply, true)
    end
end)

function PANEL:Debug_VoteEveryone()
    for _, ply in player.Iterator() do
        self:VoteForMap(ply)
    end
end

function PANEL:OnMousePressed(keyCode)
    if keyCode ~= MOUSE_LEFT then return end
    if debugvgui == true then
        --self:Debug_VoteEveryone()
        --return
    end

    self:VoteForMap(LocalPlayer())
end

vgui.Register("mapvote_SVoteIcon", PANEL, "DPanel")
