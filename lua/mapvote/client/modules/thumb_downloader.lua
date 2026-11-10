-- for autorefresh, otherwise VERY annoying issues arise with debugging
local ThumbDownloader = {
    workshopIDLookup = {},
    workshopIDToMap = {},
    mapsToDownload = {},
    ---@type table<string, fun( filepath: string )>
    urlOverrides = {},
    searchPaths = {"materials/mapvote/thumb_overrides/", "maps/thumb", "maps/thumb/", "maps/", "data/mapvote/thumb_cache/",},
    noIcon = "maps/thumb/noicon.png",
    thumbFilePathCache = {},
}

MapVote.ThumbDownloader = ThumbDownloader
MapVote.ThumbDownloader.downloadedMaps = MapVote.ThumbDownloader.downloadedMaps or {}
MapVote.ThumbDownloader.workshopIDToMap = MapVote.ThumbDownloader.workshopIDToMap or {}
-- TODO all net receivers should be in net.lua
net.Receive("MapVote_WorkshopIDTable", function()
    ThumbDownloader.workshopIDLookup = net.ReadTable()
    PrintTable(ThumbDownloader.workshopIDLookup)
    print("\n\n\n\n\n\n")
    for map, wsid in pairs(ThumbDownloader.workshopIDLookup) do
        print(wsid, map)
        ThumbDownloader.workshopIDToMap[wsid] = map
    end

    print(string.format("MapVote: Received %s workshop IDs", table.Count(ThumbDownloader.workshopIDLookup)))
    ThumbDownloader:DownloadAll()
end)

net.Receive("MapVote_SingleWorkshopID", function()
    local map = net.ReadString()
    local wsid = net.ReadString()
    print(wsid, map, "HIII")
    ThumbDownloader.workshopIDToMap[wsid] = map
    ThumbDownloader.workshopIDLookup[map] = wsid
    local callback = ThumbDownloader:GetCallbackOfMap(map)
    ThumbDownloader:DownloadSingly(map, callback)
end)

function ThumbDownloader:getMapThumbnailFilePath(name)
    if self.thumbFilePathCache[name] then return self.thumbFilePathCache[name] end
    for _, path in ipairs(self.searchPaths) do
        -- finding all the paths in bulk this way is faster than using file.Exists
        local thumbs = file.Find(path .. "*", "GAME")
        for _, thumb in ipairs(thumbs) do
            local extensionName = string.sub(thumb, -3, -1)
            if extensionName == "png" or extensionName == "jpg" then
                local mapName = string.sub(thumb, 1, -5)
                self.thumbFilePathCache[mapName] = path .. thumb
            end
        end
    end
    return self.thumbFilePathCache[name]
end

---@param map string
---@param callback fun( filepath: string )
function ThumbDownloader:QueueDownload(map, callback)
    local filePath = self:getMapThumbnailFilePath(map)
    if filePath then
        local mat = Material(filePath)
        --self.downloadedMaps[map] = mat
        --callback( mat )
        --return
    end

    if self.downloadedMaps[map] then
        callback(self.downloadedMaps[map])
        return
    end

    PrintTable(self.downloadedMaps)
    print("MapVote: Queued map thumb for download", map)
    table.insert(self.mapsToDownload, {
        map = map,
        callback = callback
    })
end

---@param map string
---@param url string
function ThumbDownloader:SetURLOverride(map, url)
    self.urlOverrides[map] = url
end

function ThumbDownloader:RequestWorkshopIDs()
    if #self.mapsToDownload == 0 then return end
    local mapsNeedingIDs = {}
    for _, mapData in pairs(self.mapsToDownload) do
        local map = mapData.map
        if not self.urlOverrides[map] then table.insert(mapsNeedingIDs, map) end
    end

    MapVote.Net.requestWorskhopIDs(mapsNeedingIDs)
end

function ThumbDownloader:GetCallbackOfMap(map)
    print("Getting callback")
    for _, mapData in pairs(self.mapsToDownload) do
        if mapData.map == map then
            print("MapVote: got callback for map " .. map)
            return mapData.callback
        end
    end
end

function ThumbDownloader:RequestSingleWorkshopID(map)
    local callback = self:GetCallbackOfMap(map) -- why do i have to do this? there must be a better way
    --[[
    -- this isn't needed anymore?
    if self.workshopIDLookup[map] then
        print("MapVote: single WSID already requested, returning to download singly: " .. map)
        self:DownloadSingly(map, callback)
        return
    end
    --]]
    print("MapVote: requesting single WSID for map " .. map)
    MapVote.Net.requestSingleWorkshopID(map, callback)
end

function ThumbDownloader:DownloadSingly(map, callback)
    print("MapVote: Downloading single map " .. map)
    local wsid = self.workshopIDLookup[map]
    if self.downloadedMaps[map] then
        print("MapVote: Map already downloaded, calling back")
        callback(self.downloadedMaps[map])
    end

    if self.urlOverrides[map] then
        self:DownloadThumbnailURL(map, self.urlOverrides[map], callback)
    elseif wsid then
        print("!!!!!!!!!!")
        self:DownloadThumbnailSteam(wsid, callback)
    else
        print("MapVote: no icon found for " .. map)
        callback(Material(self.noIcon))
    end

    table.RemoveByValue(self.mapsToDownload, map)
end

function ThumbDownloader:DownloadAll()
    print("MapVote: Downloading all queued map thumbs")
    for _, mapData in pairs(self.mapsToDownload) do
        local map = mapData.map
        local callback = mapData.callback
        if self.downloadedMaps[map] then
            callback(self.downloadedMaps[map])
            return
        end

        local wsid = self.workshopIDLookup[map]
        if self.urlOverrides[map] then
            self:DownloadThumbnailURL(map, self.urlOverrides[map], callback)
        elseif wsid then
            print("!!!!!!!!!")
            self:DownloadThumbnailSteam(wsid, callback)
        else
            print("SAD")
            callback(Material(self.noIcon))
        end
    end

    self.mapsToDownload = {}
end

function ThumbDownloader:DownloadThumbnailSteam(wsid, callback)
    print("MapVote: downloading thumbnailsteam for " .. wsid)
    if not wsid then
        error("No WSID given")
        return
    end

    local MAT_ERROR = Material(self.noIcon)
    steamworks.FileInfo(wsid, function(result)
        if self.workshopIDToMap[wsid] and self.downloadedMaps[self.workshopIDToMap[wsid]] then
            print("YES!")
            print(self.downloadedMaps[self.workshopIDToMap[wsid]])
            callback(self.downloadedMaps[self.workshopIDToMap[wsid]])
        end

        if not result then
            print("MapVote: no result for " .. wsid)
            callback(MAT_ERROR)
            return
        end

        if not result.previewid then
            print("MapVote: no previewid for " .. wsid)
            callback(MAT_ERROR)
            return
        end

        -- If we already have this icon downloaded, create a material from the file
        local path = "cache/workshop/" .. result.previewid .. ".cache"
        if file.Exists(path, "MOD") then
            print("HAW")
            local mat = AddonMaterial(path)
            if self.workshopIDToMap[wsid] then
                print("YES!")
                self.downloadedMaps[self.workshopIDToMap[wsid]] = mat
            end

            callback(mat)
            return
        end

        -- Download the preview image
        steamworks.Download(result.previewid, false, function(filePath)
            if not filePath then
                callback(MAT_ERROR)
                return
            end

            local mat = AddonMaterial(path)
            print("YEEEAAAAHH")
            if self.workshopIDToMap[wsid] then self.downloadedMaps[workshopIDToMap[wsid]] = mat end
            callback(mat)
        end)
    end)
end

function ThumbDownloader:DownloadThumbnailURL(name, url, callback)
    print("MapVote: downloading thumbnailurl for ", name, url)

    file.CreateDir("mapvote/thumb_cache")
    local request = {
        failed = function(err)
            print("MapVote: Failed to download map thumb", err)
            callback(Material(self.noIcon))
        end,
        success = function(code, body, headers)
            if code < 200 or code > 299 then
                print("MapVote: Failed to download map thumb, status code: ", code)
                return
            end

            local ext = ".png"
            if headers["Content-Type"] == "image/jpeg" then ext = ".jpg" end
            local filepath = "mapvote/thumb_cache/" .. name .. ext
            print("MapVote: Downloaded map thumb", name, filepath)
            file.Write(filepath, body)
            callback(Material("data/" .. filepath))
        end,
        method = "GET",
        url = url,
        headers = {},
        timeout = 5,
    }

    HTTP(request)
end
