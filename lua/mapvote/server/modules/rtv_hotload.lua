
--[[-----------------
    Useful functions
-------------------]]
local function DelayPrintMessage(HUDTYPE, message)
    timer.Simple(0, function() PrintMessage(HUDTYPE, message) end)
end

local PLAYERMETA = FindMetaTable("Player")
function PLAYERMETA:DelayPrintMessage(HUDTYPE, message)
    timer.Simple(0, function() self:PrintMessage(HUDTYPE, message) end)
end

--[[-----------------
    Rest
-------------------]]
-- this requires my fork of raphael's gma-writer to work https://github.com/greyliterature/gmod-lua-gma-writer/blob/main/gma.lua
-- ill have to add it to the modules folder probably. 
-- i havent asked for permission from raphael to put his gma-writer code directly in another repo so when this concept is closer to being finished i will do that.
-- do later:
-- disable hotloading by default with a convar and only run anything in here if its set to 1
require("workshop") -- https://github.com/WilliamVenner/gmsv_workshop
-- this is tested with 32 bit windows gmsv_workshop on a p2p server
--
-- maybe this json can be reduced or accounted for in the gma parser itself. (not very much space but still unnecessary)
local addonjson = [[ 
    {
        "title": "My Server Content",
        "type": "ServerContent",
        "tags": [
            "roleplay",
            "realism"
        ],
        "ignore": [
            "placeholder",
        ]
    }
]]
local UnwhitelistedExtensions = {
    -- these arent part of the file.write whitelist, and will cause bugs if they arent handled for / bypassed
    -- only 2 unwhitelisted extensions are accounted for. DuplicatedToStrippedGMA will probably break if theres more unwhitelisted extensions not accounted for, because
    -- of how the successrequirement variable works in there, so
    -- fix that later
    "bsp",
    "pcf",
    "ain",
}

local function DuplicateToStrippedGMA(filepath, callback) -- rewrite the gma but without all the lua
    -- this makes a folder in data/strippedhotloadgmas of the extracted gma
    -- then it takes the stripped, extracted contents and packs it into another gma
    -- this is done so that the server can mount any map gma it wants without getting backdoored by random lua in the addon downloaded with steamworks.DownloadUGC
    -- this also seems very inefficient. it parses the gma, rewrites it, then packs it into another gma.
    -- could probably do something with file:meta() functions to not be so redundant
    local wsid = string.match(filepath, ".*/(%d+)%.gma$")
    local NewGMAPath = "strippedhotloadgmas/" .. wsid
    file.CreateDir(NewGMAPath)
    file.Write(NewGMAPath .. "/" .. "addon.json", addonjson)
    local files = GMA.Read(filepath, false, "GAME").Files
    local successrequirement = table.Count(files)
    local successes = 0
    local ExtensionsToBypass = {}
    for k, tbl in ipairs(files) do
        local OriginalPath = tbl.Name
        local DirectoryPath = string.match(OriginalPath, "^(.*)/[^/]+$")
        if string.lower(string.sub(DirectoryPath, 1, 3)) == "lua" then
            print("not duplicating " .. DirectoryPath)
            successrequirement = successrequirement - 1
            continue
        end

        file.CreateDir(NewGMAPath .. "/" .. DirectoryPath)
        local filename = NewGMAPath .. "/" .. OriginalPath
        for i = 1, #UnwhitelistedExtensions do
            local extension = UnwhitelistedExtensions[i]
            if string.EndsWith(OriginalPath, extension) == true then -- fix for .bsp, .pcf, etc not being in file.write whitelist
                --continue
                OriginalPath = OriginalPath .. ".txt"
                ExtensionsToBypass[extension .. ".txt"] = true
                filename = filename .. ".txt"
                print("bypassing " .. filename)
            end
        end

        local succ = file.Write(filename, "")
        if succ then
            local f = file.Open(NewGMAPath .. "/" .. OriginalPath, "wb", "DATA")
            f:Write(tbl.Content)
            f:Close()
            successes = successes + 1
            --print(successes, successrequirement, "C")
            if successes == successrequirement then -- create gma when every single file is done
                -- note: gma.create uses input relative to DATA, but output relative to GAME
                if file.Exists(NewGMAPath .. ".gma", "DATA") == true then -- if the GMA file already exists, then it's probably safe to use that instead of making a new gma (it also prevents errors, because game.mountgma makes the file.open in gma.create -> gma.build() not work)
                    print("GMA already mounted, calling back with old gma")
                    callback("data/" .. NewGMAPath .. ".gma")
                    return
                end

                GMA.Create(NewGMAPath .. ".gma", "data" .. "/" .. NewGMAPath, true, false, function(gmapath)
                    --
                    callback(gmapath)
                    DelayPrintMessage(HUD_PRINTTALK, "Made " .. gmapath)
                end, ExtensionsToBypass)
            end
        else
            ErrorNoHaltWithStack("Failed writing " .. NewGMAPath .. "/" .. OriginalPath .. "\n")
            callback(nil) -- fail! callback to HotloadMap and tell it to just load the second most voted (non hotloaded) map.
        end
        --print(DirectoryPath)
        --]]
    end
    --callback(nil)
    -- this callback(nil) was here before and was probably important so im leaving it commented here. revisit later
end

local HotloadedMaps = {}
--[[
local function FindMapWorkshopID(mapname) -- unused, should make initpostentity use this, move the sql stuff into here and just call that
    for k, v in ipairs(engine.GetAddons()) do
        print(k)
        PrintTable(v)
    end
end
--]]
--FindMapWorkshopID("ap_aerowalk")
local function WriteHotloadedMapToSQL(mapname, wsid) -- map name with ".bsp" by the way
    local firstoperation = sql.QueryTyped("CREATE TABLE IF NOT EXISTS hotloaded_maps (mapname TEXT, wsid TEXT)")
    if firstoperation == false then
        error("first operation failed" .. sql.LastError())
        return
    end

    local secondoperation = sql.QueryTyped("INSERT INTO hotloaded_maps (mapname, wsid) VALUES (?, ?)", mapname, wsid)
    if secondoperation == false then
        error("second operation failed" .. sql.LastError())
        return
    end

    print("successfully wrote " .. mapname .. ", " .. wsid .. " to sql")
end

local DownloadedPathsCache = {}
function steamworks.DownloadUGC_CACHED(wsid, callback)
    if DownloadedPathsCache[wsid] then
        print("returning cached wsid: " .. wsid .. ", cached path: " .. DownloadedPathsCache[wsid])
        callback(DownloadedPathsCache[wsid], _)
        return
    end

    print("downloading new " .. wsid)
    steamworks.DownloadUGC(wsid, function(path, fileobject)
        DownloadedPathsCache[wsid] = path
        PrintTable(DownloadedPathsCache)
        callback(path, fileobject)
    end)
end

local AlreadyMountedWSIDs = {} -- prevent errors in GMA.create -> GMA.build about it complaining about not being able to open (mounted?) gma files
local function HotloadMap(wsid, callback) -- this should only mount if the map is voted on, not always
    steamworks.DownloadUGC_CACHED(wsid, function(path, fileobject)
        -- the file
        print("remember to delete the original gma file in " .. path .. ".\nthis function does not delete it by itself. will figure out a way to do this through api or something eventually.")
        -- inconvenient, solve this later
        -- maybe something can be done with the fileobject given, not sure
        DuplicateToStrippedGMA(path, function(gmapath)
            if not gmapath then
                ErrorNoHaltWithStack("gmapath is nil")
                -- at this point you should be giving up and loading another map, or cancelling the RTV. 
                return
            end

            --DelayPrintMessage(HUD_PRINTTALK, "Made stripped GMA at " .. gmapath)
            if AlreadyMountedWSIDs[wsid] then
                print(wsid .. " was already mounted, returning")
                return
            end

            local succ, files = game.MountGMA(gmapath)
            if succ == true then
                AlreadyMountedWSIDs[wsid] = true
                DelayPrintMessage(HUD_PRINTTALK, "Mounted stripped GMA")
                for _, filename in ipairs(files) do
                    if string.EndsWith(filename, ".bsp") then --
                        filename = string.GetFileFromFilename(filename)
                        WriteHotloadedMapToSQL(filename, wsid)
                        HotloadedMaps[filename] = wsid
                        DelayPrintMessage(HUD_PRINTTALK, "Mounted " .. filename)
                    end
                end

                callback(true)
            else
                error("failed to mount GMA")
                callback(false)
            end
        end)
    end)
end

local matchedDirs = {}
local function recurseListContents(path, first) -- this is from example #2, won't let me link it properly https://wiki.facepunch.com/gmod/file.Find#example
    -- do not fill in arg[2]! that is for the function itself to fill (could do a local bool above the function instead, but it fulfills its purpose, whatever, maybe later).
    local files, dirs = file.Find(path .. "*", "DATA")
    local matchedFiles = {}
    matchedDirs = (first == nil and {}) or matchedDirs
    for _, v in ipairs(files) do
        local fullPath = path .. v
        table.insert(matchedFiles, fullPath)
    end

    for _, dir in ipairs(dirs) do
        local subFiles = select(1, recurseListContents(path .. dir .. "/", false))
        for _, file in ipairs(subFiles) do
            table.insert(matchedFiles, file)
        end

        table.insert(matchedDirs, path .. dir)
    end
    return matchedFiles, matchedDirs
end

hook.Add("InitPostEntity", "AddWorkshopForHotloadedMap", function()
    if (RealTime() < 30 and game.IsDedicated() == true) or (game.IsDedicated() == false and game.GetMapChangeCount() == 1) then -- if realtime is less than 30 the server recently started, therefore
        -- the table recording mounted gmas / hotloaded_maps doesn't matter, so
        -- delete that table so it doesn't grow too large. 
        -- the game.IsDedicated check is for listen servers. (since gmas never unmount, even when a listenserver gets shut down, to my knowledge).
        if sql.TableExists("hotloaded_maps") then
            sql.QueryTyped("DELETE FROM hotloaded_maps")
            print("deleted hotloaded_maps table, server recently started")
        end

        --
        -- if the server / game is recently up, we can safely remove all the gmas (since they are not mounted anymore). 
        -- we cannot remove a map's gma right after changeleveling to it unfortunately, because mounting a gma makes it open until the game is closed.
        local PathsToDelete, DirsToDelete = recurseListContents("strippedhotloadgmas/")
        for _, filepath in PathsToDelete do
            file.Delete(filepath)
            --print("deleted " .. filepath)
        end

        for _, filepath in ipairs(DirsToDelete) do -- you cant delete a directory until all of its subfolders and subfiles are deleted, apparently
            file.Delete(filepath)
            --print("deleted " .. filepath)
        end

        print("deleted strippedhotloadgmas/ folder, server recently started")
        return
    end

    if sql.TableExists("hotloaded_maps") then
        local CheckIfCurrentMapIsInSQLTable = sql.QueryTyped("SELECT * FROM hotloaded_maps WHERE mapname = ?", game.GetMap() .. ".bsp") -- move this to FindMapWorkshopID() later probably
        if CheckIfCurrentMapIsInSQLTable == false then
            error("CheckIfCurrentMapIsInSQLTable failed" .. (sql.LastError() or ""))
            return
        end

        local wsid = nil
        if CheckIfCurrentMapIsInSQLTable[1] then
            wsid = CheckIfCurrentMapIsInSQLTable[1]["wsid"]
            -- there should be an else statement here that errors if the map is not in engine.GetAddons(), but still exists.
            -- that would mean that the map has been hotloaded, but the sql table somehow wasnt updated, so then it should 
            -- error to tell the server about this. this is easily testable by destroying the listenserver and reconnecting, then loading to a hot loaded map. 
            -- maybe if this happens it should load to the server's default map (otherwise no one would be able to connect, which would kill server pop, so might as well switch to default map)
            -- do this later.
            print("Read this comment and do it later")
        end

        if not wsid then return end
        print("Current map is in hotloaded_maps table, " .. "resource.AddWorkshop(" .. wsid .. ")")
        resource.AddWorkshop(wsid)
        -- "Gamemodes that are workshop enabled and the current map are automatically added to this list, if they come from the servers' workshop collection - so there's no need to manually add them."
        -- from https://wiki.facepunch.com/gmod/resource.AddWorkshop
        -- the hotloaded maps, however, are not automatically added, so
        -- if you don't do this clients will get "map is missing" (and something about NET_MAXFILESIZEFRAGMENTS limit will print in the console) when loading into the server
    end
end)

--[[---------------
    Storage cleanup
-----------------]]
local ENV, _ = file.Find("mapvote/env.txt", "DATA")
if not ENV then
    file.Write("mapvote/env.txt", {
        SERVER_URL = "", -- https://gamecp.physgun.com/server/XXXXXXXX <--
        ACCOUNTTOKEN = "" -- get this at https://gamecp.physgun.com/account/security and paste it here
    })
end

local color_red = Color(255, 0, 0)
ENV = util.JSONToTable(file.Read("mapvote/env.txt", "DATA"))
local SERVER_TOKEN = ENV.ACCOUNTTOKEN -- this is used to delete lingering hotloaded gmas in cache/scrds and steam_cache
local SERVER_URL = ENV.SERVER_URL -- this is used for the api links
local function DeleteLingeringHotloadedGMAs()
    if not SERVER_URL or not SERVER_TOKEN then
        local FilePath = debug.getinfo(function() end).short_src
        MsgC(color_red, "SERVER_URL / ACCOUNTTOKEN not provided, returning.\nThis means you will have to manually delete the gma files accumulated in cache/scrds and steam_cache, since the script can't do it for you.\nRead the top of the file @ " .. FilePath .. " for links on how to get them\n")
        return
    end

    local HTTPTable = {
        method = "POST",
        url = "https://gamecp.physgun.com/api/client/servers/" .. SERVER_URL .. "/files/delete",
        headers = {
            ["Content-Type"] = "application/json",
            ["Accept"] = "application/vnd.wisp.v1+json",
            ["Authorization"] = "Bearer " .. SERVER_TOKEN,
        },
        parameters = {},
        failed = function(reason) print("HTTP request failed", reason) end,
        success = function(code_2, body_2, headers_2)
            if code_2 == 204 then
                print("Deleted successfully")
            else
                print("Bad response: ", code_2, body_2)
            end
        end,
    }

    local HotloadedWSIDsQuery = sql.QueryTyped("SELECT DISTINCT wsid FROM hotloaded_maps")
    if HotloadedWSIDsQuery ~= false then
        local i = 1
        local step = 1
        timer.Create("DeleteHotloadedGMAsThroughAPI", 1, table.Count(HotloadedWSIDsQuery) * 2, function()
            -- This timer is bad! However, not sure how to tell the API to delete multiple paths. Wasted 1 hour trying to figure it out.
            local tbl = HotloadedWSIDsQuery[step]
            local cachepath = "/garrysmod/cache/srcds/" .. tbl["wsid"] .. ".gma"
            local steam_cachepath = "/steam_cache/content/4000/" .. tbl["wsid"]
            if i % 2 ~= 0 then
                print("deleting " .. cachepath)
                HTTPTable.parameters["paths[0]"] = cachepath
            else
                print("deleting " .. steam_cachepath)
                HTTPTable.parameters["paths[0]"] = steam_cachepath
                step = step + 1
            end

            HTTP(HTTPTable)
            i = i + 1
        end)
    end
end

hook.Add("InitPostEntity", "DeleteLingeringHotloadedGMAs", DeleteLingeringHotloadedGMAs)
--[[---------------
    Chat commands
-----------------]]
--Pretty much just near copies of 
-- https://github.com/greyliterature/map_vote/blob/c5a8930302c9f53f0230409e845a9e8fc1f6aa3d/lua/mapvote/server/modules/rtv.lua#L127-L157
-- since those functions do the job pretty well already
local debugging = false -- remove this after testing
--
local RTV = MapVote.RTV
local Nominate = {} -- functions table
function Nominate.CanVote(ply, wsid, mapname, ugccallback)
    local conf = MapVote.GetConfig()
    if not wsid then return false, "You must nominate a workshop id!" end
    if debugging ~= true and ply.LastVote == mapname then return false, "Already voted for this map!" end
    if conf.EnableNomination == false then return false, "Nomination is disabled!" end
    if conf.NominateWait >= CurTime() then return false, "You must wait " .. string.NiceTime(conf.NominateWait - CurTime()) .. " before voting to nominate a map!" end
    if GetGlobalBool("In_Voting") then return false, "There is currently a vote in progress!" end
    if MapVote.state.isInProgress then return false, "There is already a vote in progress" end
    if debugging ~= true and RTV.GetPlayerCount() < conf.RTVPlayerCount then return false, "You need more players before you can nominate a map!" end
    local PossibleMaps = Nominate.GetMapsFromAddon(wsid)
    if table.Count(PossibleMaps) - 1 == 0 then return false, "That addon does not have any maps!" end
    if mapname and not PossibleMaps[mapname] then return false, "That addon does not have that map!\nAvailable maps:\n" .. table.concat(PossibleMaps["Arrayed"], "\n", 1, (#PossibleMaps["Arrayed"] > 5) or #PossibleMaps["Arrayed"]) .. ((table.Count(PossibleMaps) - 1 > 5 and "\n(more...)") or "") end
    --[[
    -- This isnt needed because "That addon does not have any maps!" return (should) captures this earlier
    steamworks.FileInfo(wsid, function(data)
        -- check if the wsid is valid
        print("TETSTTING")
        if data.error == -3 then
            return false, "must nominate a valid workshop ID"
        else
            return true
        end
    end)
    --]]
end

local MapCache = {}
function Nominate.GetMapsFromAddon(wsid)
    -- do downloadugc stuff here
    local firstmap = nil
    if MapCache[wsid] then
        print("WSID already searched, returning cache")
        for _, mapname in ipairs(MapCache[wsid]["Arrayed"]) do -- this is not ordered but that's probably ok.
            firstmap = mapname
            break
        end
    else
        MapCache[wsid] = {}
        MapCache[wsid]["Arrayed"] = {} -- for table.concat, this means that all table.counts of PossibleMaps will have to be subtracted one though.
        steamworks.DownloadUGC_CACHED(wsid, function(filepath, _)
            local files = GMA.Read(filepath, false, "GAME").Files
            for k, tbl in ipairs(files) do
                local OriginalPath = tbl.Name
                local DirectoryPath = string.match(OriginalPath, "^(.*)/[^/]+$")
                if string.lower(string.sub(DirectoryPath, 1, 4)) == "maps" and string.lower(string.sub(OriginalPath, #OriginalPath - 3, #OriginalPath)) == ".bsp" then
                    local mapname = string.sub(tbl.Name, 6, #tbl.Name - 4) -- "maps/mapname.bsp" becomes just "mapname"
                    if not firstmap then firstmap = mapname end
                    MapCache[wsid][mapname] = true
                    MapCache[wsid]["Arrayed"][#MapCache[wsid]["Arrayed"] + 1] = mapname
                    print("map added to list of maps in addon " .. wsid .. ": " .. mapname)
                else
                    continue
                end
            end
        end)
    end
    return MapCache[wsid], firstmap
end

function Nominate.GetThreshold()
    if debugging == true then return 0 end
    local conf = MapVote.GetConfig()
    local totalPlayers = RTV.GetPlayerCount() -- old RTV player count function works fine for this case
    local threshold = totalPlayers * conf.NominatePercentPlayersRequired
    return math.ceil(threshold)
end

local Nominations = {} -- tracking votes by wsid
-- should make this track maps too. addons add multiple maps at a time sometimes
function Nominate.AddVote(ply, wsid, mapname)
    Nominations[mapname] = ((Nominations[mapname] and Nominations[mapname]) or 0) + 1
    ply.LastVote = mapname
    DelayPrintMessage(HUD_PRINTTALK, ply:Nick() .. " has voted to add wsid " .. wsid .. ", " .. mapname .. " to be added to the RTV list.")
end

function Nominate.MapShouldAdd(wsid)
    if MapVote.state.isInProgress then return end
    if debugging == true then return true end
    local conf = MapVote.GetConfig()
    local totalVotes = Nominations[wsid]
    local totalPlayers = RTV.GetPlayerCount()
    if totalPlayers < conf.RTVPlayerCount then return end
    if totalPlayers == 0 then return end
    return totalVotes >= Nominate.GetThreshold()
end

NominatedMaps = {}
function Nominate.AddToMapList(wsid, mapname)
    DelayPrintMessage(HUD_PRINTTALK, "Added " .. wsid .. ", " .. mapname .. " to rtv list.")
    NominatedMaps[#NominatedMaps + 1] = {wsid, mapname}
end

function Nominate.AddToMapListIfMapShouldAdd(wsid, mapname)
    if Nominate.MapShouldAdd(wsid, mapname) then
        Nominate.AddToMapList(wsid, mapname)
        return
    end
end

function Nominate.Map(ply, wsid, mapname)
    if not IsValid(ply) then return end
    local PossibleMaps, firstmap = Nominate.GetMapsFromAddon(wsid)
    if table.Count(PossibleMaps) - 1 > 1 and not mapname then
        ply:DelayPrintMessage(HUD_PRINTTALK, "That addon has multiple maps. Please send command again and specify which map you'd like to nominate (!nominate 12345 gm_mapname).\nAvailable maps:\n" .. table.concat(PossibleMaps["Arrayed"], "\n", 1, (#PossibleMaps["Arrayed"] > 5) or #PossibleMaps["Arrayed"]) .. ((table.Count(PossibleMaps) - 1 > 5 and "\n(more...)") or ""))
        return
    elseif table.Count(PossibleMaps) - 1 == 1 then
        mapname = firstmap
    end

    local can, err = Nominate.CanVote(ply, wsid, mapname)
    if can == false then
        ply:DelayPrintMessage(HUD_PRINTTALK, err)
        return
    else
        --[[
     local PossibleChoiceCommands = {} -- !gm_map1, !gm_map2, !gm_map3
        if #PossibleMaps > 1 then
            ply:DelayPrintMessage(HUD_PRINTTALK, "That addon has multiple maps. Choose which one you'd like to nominate by saying it.\nAvailable maps: \n" .. table.concat(PossibleMaps, "\n"))
                hook.Add("PlayerSay", "GetMultiMapNominationChoice", function(sender, text, _)
                    print(sender, ply)
                    if sender == ply and PossibleChoiceCommands[text] then --
                        ChosenMapName = text
                    end
                end)
            --
        else
            ChosenMapName = PossibleMaps[1]
        end
        --]]
        Nominate.AddVote(ply, wsid, mapname)
        Nominate.AddToMapListIfMapShouldAdd(wsid, mapname)
    end
end

RTV.ChatCommands["!nominate"] = function(...) Nominate.Map(...) end
hook.Add("PlayerSay", "Nominate Chat Command", function(ply, text)
    text = string.lower(text)
    args = string.Explode(" ", text) -- !command -> 123, true, false <-
    cmd = args[1] -- !command
    table.remove(args, 1)
    local f = RTV.ChatCommands[cmd]
    if f then
        f(ply, unpack(args))
        return
    end
end)

--[[---------------
    Detours
-----------------]]
MapVote._maps = nil
function MapVote.getMapList() -- need to make the original function work with hotload
    if MapVote._maps then return MapVote._maps end
    local maps = file.Find("maps/*.bsp", "GAME")
    local ValidMaps = {}
    local tblexists = sql.TableExists("hotloaded_maps")
    for i, v in ipairs(maps) do
        local mapname = string.sub(v, 1, -5)
        if tblexists == true then
            local CheckIfCurrentMapIsInSQLTable = sql.QueryTyped("SELECT * FROM hotloaded_maps WHERE mapname = ?", v) -- move this to FindMapWorkshopID() later probably
            if CheckIfCurrentMapIsInSQLTable == false then
                ErrorNoHaltWithStack("CheckIfCurrentMapIsInSQLTable failed" .. (sql.LastError() or ""))
                continue
            end

            if CheckIfCurrentMapIsInSQLTable[1] then
                --print("not adding " .. mapname .. " to rtv list.")
                continue
            end
        end

        table.insert(ValidMaps, mapname) -- strip .bsp
    end

    local conf = MapVote.GetConfig()
    if conf.EnableNomination == true then
        for i, tbl in ipairs(NominatedMaps) do
            local IndexToRemove = #ValidMaps - i
            table.remove(ValidMaps, IndexToRemove)
            print("removed " .. IndexToRemove .. " from maps list.")
            local mapname = tbl[2]
            table.insert(ValidMaps, mapname)
        end
    end

    MapVote._maps = ValidMaps
    return ValidMaps
end

hook.Add("MapVote_ChangeMap", "DelayMapChangeIfHotloaded", function(map)
    for _, tbl in ipairs(NominatedMaps) do
        local mapname = tbl[2]
        if mapname == map then --
            return false
        end
    end
end)

hook.Add("MapVote_VoteFinished", "ChangeMapOnMount", function(resultstable)
    --
    local winningmap = resultstable.state.currentMaps[resultstable.winner]
    local secondwinningmap = resultstable.state.currentMaps[resultstable.winner - 1]
    for _, tbl in ipairs(NominatedMaps) do
        local wsid = tbl[1]
        local mapname = tbl[2]
        if mapname == winningmap then
            HotloadMap(wsid, function(succ)
                if succ == true then
                    PrintMessage(HUD_PRINTTALK, "Attempting to change level to hotloaded map " .. wsid .. ", " .. mapname)
                    RunConsoleCommand("changelevel", mapname)
                else
                    PrintMessage(HUD_PRINTTALK, "Failed to mount GMA of " .. wsid .. "changing map to second highest winner.")
                    RunConsoleCommand("changelevel", secondwinningmap)
                end
            end)

            break
        end
    end
end)
