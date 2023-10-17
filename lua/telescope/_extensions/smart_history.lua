local histories = require("telescope.actions.history")
local actions = require("telescope.actions")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local make_entry = require("telescope.make_entry")
local conf = require("telescope.config").values
local actions_state = require("telescope.actions.state")

local escape = function(content)
	return string.format("__ESCAPED__'%s'", content)
end

local unescape = function(content)
	return content:gsub("^__ESCAPED__'(.*)'$", "%1")
end

local M = {
	db_path = "/home/suglow/dotfiles/lazynv/.lazynv/.local/share/lazynv/telescope_history.sqlite3",
	db = nil,
	data = nil,
}

local fetch_cont_cwd = function(db_tbl)
	local contents = {}
	local cwds = {}
	local visitor = {}
	for _, v in ipairs(db_tbl) do
		local code = unescape(v.content) .. "|" .. v.cwd
		if not visitor[code] then
			local content = unescape(v.content)
			table.insert(contents, content)
			table.insert(cwds, v.cwd)
			visitor[code] = true
		end
	end
	return contents, cwds
end

local fetch_items = function()
	if M.data == nil then
		if M.db_path == nil then
			return
		end
		local has_sqlite, sqlite = pcall(require, "sqlite")
		if not has_sqlite then
			return
		end
		M.db = sqlite.new(M.db_path)
		M.data = M.db:tbl("history", {
			id = true,
			content = "text",
			picker = "text",
			cwd = "text",
		})
	end

	local current_tbl = M.data:get({
		where = {
			picker = "Live Grep",
		},
	})
	return fetch_cont_cwd(current_tbl)
end

local function show_grep_history(opts)
	opts = opts or { show_line = false }
	local conts, cwds = fetch_items()
	if conts == nil or cwds == nil then
		return
	end
	-- reverse the list
	local sorted_list = {}
	for i = #conts, 1, -1 do
		table.insert(sorted_list, { conts[i], cwds[i], #conts - i + 1 })
	end

	pickers
		.new(opts, {
			prompt_title = "Grep History",
			finder = finders.new_table({
				results = sorted_list,
				entry_maker = function(entry)
					return {
						value = entry,
						display = entry[1] .. " | " .. entry[2],
						ordinal = entry[1],
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			attach_mappings = function(bufnr, _)
				actions.select_default:replace(function()
					actions.close(bufnr)
					local selection = actions_state.get_selected_entry()

					local name = selection.value[1]
					local cwd = selection.value[2]
					local opt = {
						default_text = name,
						cwd = cwd,
					}
					require("telescope.builtin").live_grep(opt)
				end)
				return true
			end,
		})
		:find()
end

local get_smart_history = function()
	local has_sqlite, sqlite = pcall(require, "sqlite")
	if not has_sqlite then
		if type(sqlite) ~= "string" then
			print("Coundn't find sqlite.lua. Using simple history")
		else
			print("Found sqlite.lua: but got the following error: " .. sqlite)
		end
		return histories.get_simple_history()
	end

	local ensure_content = function(self, picker, cwd)
		if self._current_tbl then
			return
		end
		self._current_tbl = self.data:get({
			where = {
				picker = picker,
				cwd = cwd,
			},
		})
		self.content = {}
		for k, v in ipairs(self._current_tbl) do
			self.content[k] = unescape(v.content)
		end
		self.index = #self.content + 1
	end

	return histories.new({
		init = function(obj)
			obj.db = sqlite.new(obj.path)
			M.path = obj.path
			obj.data = obj.db:tbl("history", {
				id = true,
				content = "text",
				picker = "text",
				cwd = "text",
			})

			obj._current_tbl = nil
		end,
		reset = function(self)
			self._current_tbl = nil
			self.content = {}
			self.index = 1
		end,
		append = function(self, line, picker, no_reset)
			local title = picker.prompt_title
			local cwd = picker.cwd or vim.loop.cwd()

			if line ~= "" then
				ensure_content(self, title, cwd)
				if self.content[#self.content] ~= line then
					table.insert(self.content, line)

					local len = #self.content
					if self.limit and len > self.limit then
						local diff = len - self.limit
						local ids = {}
						for i = 1, diff do
							if self._current_tbl then
								table.insert(ids, self._current_tbl[i].id)
							end
						end
						self.data:remove({ id = ids })
					end
					self.data:insert({ content = escape(line), picker = title, cwd = cwd })
				end
			end
			if not no_reset then
				self:reset()
			end
		end,
		pre_get = function(self, _, picker)
			local cwd = picker.cwd or vim.loop.cwd()
			ensure_content(self, picker.prompt_title, cwd)
		end,
	})
end

return require("telescope").register_extension {
  setup = function(_, config)
    if config.history ~= false then
      config.history.handler = function()
        return get_smart_history()
      end
    end
  end,
  exports = {
    smart_history = function()
      return show_grep_history()
    end,
  },
}
