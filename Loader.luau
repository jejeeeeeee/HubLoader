if _G.DaHoodSSPHasBeenLoadedAlreadySoTheyCantRunItAgainToPreventDoubleExecutionAndGlitchesWithTheMenu then
	warn("To prevent Double Execution and Menu glitches you cannot execute this twice")
	return
end

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RbxAnalyticsService = game:GetService("RbxAnalyticsService")

local LocalPlayer = Players.LocalPlayer

local FirebaseDatabaseUrl = "https://dahoodsspkeys-8e3f6-default-rtdb.europe-west1.firebasedatabase.app/"
local FirebaseKeysPath = "Keys"
local FirebaseGitHubTokenPath = "GitHubToken"
local FirebaseAuthSecret = "s17Qi1xYY5CI2HlXvDHqlLheWswOJ2HpjbRZ9nIV"

local AdminPanelLibUrl = "https://raw.githubusercontent.com/jejeeeeeee/GlobalScripts/main/HubLibs/DaHoodAdminPanelLib.luau"

local SupportedGames = {
	["DaHood"] = {
		Name = "Da Hood",
		PlaceIds = {
			2788229376,
			7213786345,
			16033173781,
		},
		LoaderUrl = "https://raw.githubusercontent.com/jejeeeeeee/GlobalScripts/main/Loaders/DHMenuLoader.luau",
	},
	["MurderMystery2"] = {
		Name = "Murder Mystery 2",
		PlaceIds = {
			142823291,
			335132778,
			635183880,
		},
		LoaderUrl = "https://raw.githubusercontent.com/jejeeeeeee/GlobalScripts/main/Loaders/MM2MenuLoader.luau",
	},
}

local DefaultGameKey = "DaHood"
local SelectedGameKey = nil

local function DetectGame()
	local CurrentPlaceId = game.PlaceId
	for GameKey, GameInfo in pairs(SupportedGames) do
		if table.find(GameInfo.PlaceIds, CurrentPlaceId) then
			return GameKey, GameInfo
		end
	end
	return DefaultGameKey, SupportedGames[DefaultGameKey]
end

local function GetTargetLoaderUrl()
	local ActiveKey = SelectedGameKey or DetectGame()
	local GameConfig = SupportedGames[ActiveKey] or SupportedGames[DefaultGameKey]
	return GameConfig.LoaderUrl, GameConfig.Name
end

local GitHubAccessToken = ""
local IsVerifying = false
local TwelveHours = 12 * 60 * 60

local function GetClientHwid()
	if typeof(gethwid) == "function" then
		local Success, Result = pcall(gethwid)
		if Success and typeof(Result) == "string" and Result ~= "" then return Result end
	end

	local AnalyticsSuccess, ClientId = pcall(function() return RbxAnalyticsService:GetClientId() end)
	if AnalyticsSuccess and typeof(ClientId) == "string" and ClientId ~= "" then return ClientId end

	return tostring(LocalPlayer and LocalPlayer.UserId or "UnknownHwid")
end

local function GetHttpRequestFunction()
	if typeof(request) == "function" then return request end
	if typeof(http_request) == "function" then return http_request end
	if typeof(http) == "table" and typeof(http.request) == "function" then return http.request end
	if typeof(syn) == "table" and typeof(syn.request) == "function" then return syn.request end
	if typeof(fluxus) == "table" and typeof(fluxus.request) == "function" then return fluxus.request end
	return nil
end

local function SendHttpRequest(TargetUrl, Method, CustomHeaders, BodyString)
	local RequestFunction = GetHttpRequestFunction()
	local HeadersTable = CustomHeaders or {}

	if RequestFunction then
		local RequestOptions = {
			Url = TargetUrl,
			url = TargetUrl,
			Method = Method or "GET",
			method = Method or "GET",
			Headers = HeadersTable,
			headers = HeadersTable,
			Body = BodyString,
			body = BodyString
		}
		local Success, Response = pcall(RequestFunction, RequestOptions)
		if Success and typeof(Response) == "table" then
			local Body = Response.Body or Response.body or Response.data or ""
			local StatusCode = tonumber(Response.StatusCode or Response.Status or Response.status_code or Response.statusCode)
			if not StatusCode and Response.Success ~= nil then
				StatusCode = Response.Success and 200 or 500
			end
			StatusCode = StatusCode or (Body ~= "" and 200 or 0)
			return (StatusCode >= 200 and StatusCode < 300), tostring(Body), StatusCode
		end
	end

	local AsyncSuccess, AsyncResponse = pcall(function()
		return HttpService:RequestAsync({Url = TargetUrl, Method = Method or "GET", Headers = HeadersTable, Body = BodyString})
	end)

	if AsyncSuccess and AsyncResponse then
		local Body = AsyncResponse.Body or AsyncResponse.body or ""
		local StatusCode = tonumber(AsyncResponse.StatusCode or AsyncResponse.Status) or 200
		return AsyncResponse.Success, tostring(Body), StatusCode
	end

	if (Method == nil or Method == "GET") and next(HeadersTable) == nil then
		local GetSuccess, GetBody = pcall(function() return game:HttpGet(TargetUrl) end)
		if GetSuccess and typeof(GetBody) == "string" and GetBody ~= "" then return true, GetBody, 200 end
	end

	return false, "", 0
end

local function BuildFirebaseEndpointUrl(SubPath)
	local BaseUrl = FirebaseDatabaseUrl:gsub("/+$", "")
	local Endpoint = BaseUrl .. "/" .. SubPath .. ".json"
	if FirebaseAuthSecret ~= "" then Endpoint = Endpoint .. "?auth=" .. HttpService:UrlEncode(FirebaseAuthSecret) end
	return Endpoint
end

local function SendFirebaseJsonRequest(TargetUrl, Method, PayloadTable)
	local EncodedBody = PayloadTable and HttpService:JSONEncode(PayloadTable) or nil
	local JsonHeaders = {["Content-Type"] = "application/json"}
	return SendHttpRequest(TargetUrl, Method, JsonHeaders, EncodedBody)
end

local function FetchGitHubTokenFromFirebase()
	if GitHubAccessToken ~= "" then return GitHubAccessToken end

	local TokenEndpoint = BuildFirebaseEndpointUrl(FirebaseGitHubTokenPath)
	local FetchSuccess, ResponseBody = SendFirebaseJsonRequest(TokenEndpoint, "GET", nil)

	if FetchSuccess and ResponseBody and ResponseBody ~= "" and ResponseBody ~= "null" then
		local DecodeSuccess, DecodedToken = pcall(function() return HttpService:JSONDecode(ResponseBody) end)
		if DecodeSuccess and typeof(DecodedToken) == "string" and DecodedToken ~= "" then
			GitHubAccessToken = DecodedToken:gsub("^%s+", ""):gsub("%s+$", "")
						return GitHubAccessToken
		end
	end

	return GitHubAccessToken
end

local function ConvertRawUrlToGitHubApiUrl(RawUrl)
	local Owner, Repo, Branch, FilePath = string.match(tostring(RawUrl or ""), "^https?://raw%.githubusercontent%.com/([^/]+)/([^/]+)/([^/]+)/(.+)$")
	if not Owner or not Repo or not Branch or not FilePath then return nil end
	return string.format("https://api.github.com/repos/%s/%s/contents/%s?ref=%s", Owner, Repo, FilePath, Branch)
end

local function FetchUrlWithGitHubAuth(TargetUrl)
	local CleanUrl = tostring(TargetUrl or "")
	local IsGitHubUrl = string.find(CleanUrl, "githubusercontent.com", 1, true) ~= nil or string.find(CleanUrl, "api.github.com", 1, true) ~= nil

	local DirectSuccess, DirectBody = SendHttpRequest(CleanUrl, "GET", nil, nil)
	if DirectSuccess and typeof(DirectBody) == "string" and DirectBody ~= "" and not string.find(DirectBody, "^404:") then
		return DirectBody
	end

	local ActiveToken = FetchGitHubTokenFromFirebase()
	local HasToken = typeof(ActiveToken) == "string" and ActiveToken ~= ""

	if IsGitHubUrl and HasToken then
		local AuthHeaders = {["Authorization"] = "Bearer " .. ActiveToken, ["Accept"] = "application/vnd.github.v3.raw", ["User-Agent"] = "RobloxClient", ["Cache-Control"] = "no-cache"}
		local ApiUrl = ConvertRawUrlToGitHubApiUrl(CleanUrl)

		if ApiUrl then
			local ApiSuccess, ApiBody = SendHttpRequest(ApiUrl, "GET", AuthHeaders, nil)
			if ApiSuccess and typeof(ApiBody) == "string" and ApiBody ~= "" and not string.find(ApiBody, "^404:") then return ApiBody end
		end

		local RawSuccess, RawBody = SendHttpRequest(CleanUrl, "GET", AuthHeaders, nil)
		if RawSuccess and typeof(RawBody) == "string" and RawBody ~= "" and not string.find(RawBody, "^404:") then return RawBody end
	end

	error("GitHub fetch failed: " .. CleanUrl)
end

local function LoadPrivateGitHubScript(TargetUrl)
	local RawSource = FetchUrlWithGitHubAuth(TargetUrl)
	if typeof(RawSource) ~= "string" or RawSource == "" then error("Failed to fetch script: " .. tostring(TargetUrl)) end

	local PatchedSource = RawSource:gsub("game:HttpGetAsync%s*%(", "_G.PrivateGitHubHttpGet("):gsub("game:HttpGet%s*%(", "_G.PrivateGitHubHttpGet(")
	local CompiledChunk, CompileError = loadstring(PatchedSource)
	if not CompiledChunk then error("Failed to compile script: " .. tostring(CompileError)) end

	return CompiledChunk(GitHubAccessToken)
end

_G.PrivateGitHubHttpGet = FetchUrlWithGitHubAuth
_G.LoadPrivateGitHubScript = LoadPrivateGitHubScript

local function SanitizeKeyForPath(RawKey)
	local Trimmed = tostring(RawKey or ""):gsub("^%s+", ""):gsub("%s+$", "")
	return Trimmed:gsub("[%.%$#%[%]%/\\]", "")
end

local function BuildFirebaseKeyUrl(SanitizedKey)
	return BuildFirebaseEndpointUrl(FirebaseKeysPath .. "/" .. SanitizedKey)
end

local function BuildFirebaseHwidQueryUrl(CurrentHwid)
	local BaseUrl = FirebaseDatabaseUrl:gsub("/+$", "")
	local QueryUrl = BaseUrl .. "/" .. FirebaseKeysPath .. ".json?orderBy=" .. HttpService:UrlEncode("\"HWID\"") .. "&equalTo=" .. HttpService:UrlEncode("\"" .. CurrentHwid .. "\"")
	if FirebaseAuthSecret ~= "" then QueryUrl = QueryUrl .. "&auth=" .. HttpService:UrlEncode(FirebaseAuthSecret) end
	return QueryUrl
end

local function IsWithinTwelveHourWindow(Timestamp)
	local Value = tonumber(Timestamp)
	if not Value then return false end
	local Age = os.time() - Value
	return Age >= 0 and Age < TwelveHours
end

local function SetTwelveHourWindowTimestamp(TargetUrl)
	local Payload = {
		TwelveHourTimeWindowTimeStamp = os.time(),
		LastUsed = os.time(),
		LastUsedRobloxAccount = LocalPlayer.Name,
		UserId = LocalPlayer.UserId
	}
	return SendFirebaseJsonRequest(TargetUrl, "PATCH", Payload)
end

local function FindKeyForHwid(CurrentHwid)
	if typeof(CurrentHwid) ~= "string" or CurrentHwid == "" then return nil, nil, "Invalid HWID." end

	local QueryUrl = BuildFirebaseHwidQueryUrl(CurrentHwid)
	local Success, ResponseBody = SendFirebaseJsonRequest(QueryUrl, "GET", nil)

	if not Success or not ResponseBody or ResponseBody == "" or ResponseBody == "null" or ResponseBody == "{}" then
		return nil, nil, nil
	end

	local DecodeSuccess, KeysData = pcall(function() return HttpService:JSONDecode(ResponseBody) end)
	if not DecodeSuccess or typeof(KeysData) ~= "table" then return nil, nil, "Failed to read Firebase key data." end

	for KeyName, KeyData in pairs(KeysData) do
		if typeof(KeyData) ~= "table" then continue end
		if KeyData.Active == false or KeyData.Banned == true or KeyData.Disabled == true then continue end

		local StoredHwid = KeyData.HWID or KeyData.Hwid or KeyData.hwid
		if tostring(StoredHwid or "") == CurrentHwid then return KeyName, KeyData, nil end
	end

	return nil, nil, nil
end

local function TryAutomaticFirebaseAuthentication(CurrentHwid)
	local KeyName, KeyData, ErrorMessage = FindKeyForHwid(CurrentHwid)

	if ErrorMessage then return false, ErrorMessage end
	if not KeyName or not KeyData then return false, "No key is linked to this HWID." end

	local WindowTimestamp = KeyData.TwelveHourTimeWindowTimeStamp
	if not WindowTimestamp then return false, "No time window found." end
	if not IsWithinTwelveHourWindow(WindowTimestamp) then return false, "12-hour window expired." end

	if typeof(KeyData.GitHubToken) == "string" and KeyData.GitHubToken ~= "" then
		GitHubAccessToken = KeyData.GitHubToken
			end

	return true, "Automatically authenticated."
end

local function VerifyAndLinkFirebaseKey(RawKey, CurrentHwid)
	local SanitizedKey = SanitizeKeyForPath(RawKey)
	if SanitizedKey == "" then return false, "Invalid key." end

	local TargetUrl = BuildFirebaseKeyUrl(SanitizedKey)
	local FetchSuccess, ResponseBody = SendFirebaseJsonRequest(TargetUrl, "GET", nil)

	if not FetchSuccess or not ResponseBody or ResponseBody == "" or ResponseBody == "null" then return false, "Invalid key." end

	local DecodeSuccess, KeyData = pcall(function() return HttpService:JSONDecode(ResponseBody) end)
	if not DecodeSuccess or KeyData == nil or KeyData == false then return false, "Invalid key." end

	if typeof(KeyData) == "boolean" and KeyData == true then
		local CurrentTime = os.time()
		local LinkPayload = {
			HWID = CurrentHwid,
			UserId = LocalPlayer.UserId,
			Username = LocalPlayer.Name,
			LinkedAt = CurrentTime,
			LastUsed = CurrentTime,
			LastUsedRobloxAccount = LocalPlayer.Name,
			TwelveHourTimeWindowTimeStamp = CurrentTime
		}
		local WriteSuccess = SendFirebaseJsonRequest(TargetUrl, "PUT", LinkPayload)
		if not WriteSuccess then return false, "Failed to link HWID to key." end
		return true, "Key linked to your HWID."
	end

	if typeof(KeyData) == "string" then
		local ExistingStringHwid = KeyData:gsub("^%s+", ""):gsub("%s+$", "")

		if ExistingStringHwid == "" or string.lower(ExistingStringHwid) == "none" or string.lower(ExistingStringHwid) == "unlinked" then
			local CurrentTime = os.time()
			local LinkPayload = {
				HWID = CurrentHwid,
				UserId = LocalPlayer.UserId,
				Username = LocalPlayer.Name,
				LinkedAt = CurrentTime,
				LastUsed = CurrentTime,
				LastUsedRobloxAccount = LocalPlayer.Name,
				TwelveHourTimeWindowTimeStamp = CurrentTime
			}
			local WriteSuccess = SendFirebaseJsonRequest(TargetUrl, "PUT", LinkPayload)
			if not WriteSuccess then return false, "Failed to link HWID to key." end
			return true, "Key linked to your HWID."
		end

		if ExistingStringHwid == CurrentHwid then
			SetTwelveHourWindowTimestamp(TargetUrl)
			return true, "Key verified."
		end

		return false, "Key is already linked to another HWID."
	end

	if typeof(KeyData) == "table" then
		if KeyData.Active == false or KeyData.Banned == true or KeyData.Disabled == true then return false, "This key has been disabled." end

		if typeof(KeyData.GitHubToken) == "string" and KeyData.GitHubToken ~= "" then
			GitHubAccessToken = KeyData.GitHubToken
					end

		local ExistingHwid = KeyData.HWID or KeyData.Hwid or KeyData.hwid

		if ExistingHwid == nil or tostring(ExistingHwid) == "" or string.lower(tostring(ExistingHwid)) == "none" or string.lower(tostring(ExistingHwid)) == "unlinked" then
			local CurrentTime = os.time()
			local LinkPayload = {
				HWID = CurrentHwid,
				UserId = LocalPlayer.UserId,
				Username = LocalPlayer.Name,
				LinkedAt = CurrentTime,
				LastUsed = CurrentTime,
				LastUsedRobloxAccount = LocalPlayer.Name,
				TwelveHourTimeWindowTimeStamp = CurrentTime
			}
			local PatchSuccess = SendFirebaseJsonRequest(TargetUrl, "PATCH", LinkPayload)
			if not PatchSuccess then
				local PutSuccess = SendFirebaseJsonRequest(TargetUrl, "PUT", LinkPayload)
				if not PutSuccess then return false, "Failed to link HWID to key." end
			end
			return true, "Key linked to your HWID."
		end

		if tostring(ExistingHwid) == CurrentHwid then
			SetTwelveHourWindowTimestamp(TargetUrl)
			return true, "Key verified."
		end

		return false, "Key is already linked to another HWID."
	end

	return false, "Invalid key."
end

local CurrentHwid = GetClientHwid()
local AutoAuthenticated, AutoAuthMessage = TryAutomaticFirebaseAuthentication(CurrentHwid)

if AutoAuthenticated then
	FetchGitHubTokenFromFirebase()
	local TargetUrl, GameName = GetTargetLoaderUrl()
	local LoadSuccess, LoadError = pcall(function() LoadPrivateGitHubScript(TargetUrl) end)
	if not LoadSuccess then warn("Failed to load " .. tostring(GameName) .. " menu:", LoadError) end
   _G.DaHoodSSPHasBeenLoadedAlreadySoTheyCantRunItAgainToPreventDoubleExecutionAndGlitchesWithTheMenu = true
else
	FetchGitHubTokenFromFirebase()

	local Library = LoadPrivateGitHubScript(AdminPanelLibUrl)

	local KeyWindow = Library:CreateWindow({Name = "DaHoodKeySystem", Width = 660, Height = 350, ShowPlayerPicker = false, BodyTopOffset = 58, ToggleKey = Enum.KeyCode.RightShift})

	local KeyTab = KeyWindow:CreateTab({Name = "KeySystem", Title = "Key System", Width = 115, Default = true})

	local AuthSection = KeyTab:CreateSection({Title = "Authentication", Subtitle = "Enter your license key to load menu"})

	local DetectedKey, DetectedGame = DetectGame()
	SelectedGameKey = DetectedKey

	local GameDropdownOptions = {}
	for _, GameInfo in pairs(SupportedGames) do
		table.insert(GameDropdownOptions, GameInfo.Name)
	end

	AuthSection:CreateDropdown({
		Placeholder = "Game: " .. DetectedGame.Name,
		Options = GameDropdownOptions,
		Default = DetectedGame.Name,
		SingleSelect = true,
		Callback = function(ChosenGameName)
			for Key, Info in pairs(SupportedGames) do
				if Info.Name == ChosenGameName then
					SelectedGameKey = Key
					break
				end
			end
		end
	})

	local StatusLabel = AuthSection:CreateLabel({Text = "Status: Waiting for license key...", Muted = true})
	local KeyInput = nil

	local function HandleKeySubmission(SubmittedKey)
		if IsVerifying then return end

		local CleanInput = tostring(SubmittedKey or (KeyInput and KeyInput:Get()) or "")

		if CleanInput:gsub("%s+", "") == "" then
			StatusLabel:SetText("Status: Please enter a key first.")
			KeyWindow:Notify("Please enter a key.", false, 4)
			return
		end

		IsVerifying = true
		StatusLabel:SetText("Status: Verifying key with Firebase...")

		task.spawn(function()
			local IsValid, StatusMessage = VerifyAndLinkFirebaseKey(CleanInput, CurrentHwid)

			if IsValid then
				local TargetUrl, GameName = GetTargetLoaderUrl()
				StatusLabel:SetText("Status: " .. tostring(StatusMessage) .. " Loading " .. tostring(GameName) .. "...")
				KeyWindow:Notify(StatusMessage, true, 3)
				task.wait(0.4)
				KeyWindow:Destroy()

				local LoadSuccess, LoadError = pcall(function() LoadPrivateGitHubScript(TargetUrl) end)
				if not LoadSuccess then warn("Failed to load " .. tostring(GameName) .. " menu:", LoadError) end
                _G.DaHoodSSPHasBeenLoadedAlreadySoTheyCantRunItAgainToPreventDoubleExecutionAndGlitchesWithTheMenu = true
			else
				StatusLabel:SetText("Status: " .. tostring(StatusMessage))
				KeyWindow:Notify(StatusMessage, false, 4)
				task.wait(0.35)
				LocalPlayer:Kick(StatusMessage)
			end

			IsVerifying = false
		end)
	end

	KeyInput = AuthSection:CreateInput({Placeholder = "Enter your license key...", ButtonText = "Verify Key", ButtonTint = "Green", Callback = function(EnteredText) HandleKeySubmission(EnteredText) end})

	AuthSection:CreateButtonRow({
		{
			Text = "Copy HWID",
			Tint = "Blue",
			Callback = function()
				local CopyFunction = setclipboard or toclipboard or (Clipboard and Clipboard.set)

				if typeof(CopyFunction) == "function" then
					pcall(CopyFunction, CurrentHwid)
					KeyWindow:Notify("HWID copied to clipboard.", true, 4)
				else
					KeyWindow:Notify("HWID: " .. CurrentHwid, true, 6)
				end
			end
		},
		{
			Text = "Unload Key Panel",
			Tint = "Red",
			Callback = function()
				KeyWindow:Destroy()
			end
		}
	})
end
