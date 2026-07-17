-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- PT keyboard: ç → ] and Ç → [ (avoids ⌥+8/9 for bracket navigation)
vim.keymap.set({ "n", "x", "o" }, "ç", "]", { remap = true })
vim.keymap.set({ "n", "x", "o" }, "Ç", "[", { remap = true })

-- PT keyboard: \ → vertical split (| requires modifier on PT layout)
vim.keymap.set("n", "<leader>\\", "<C-W>v", { desc = "Split right", remap = true })

-- Send the visual selection to the tmux annotate popup (annotate.sh), with a
-- file:line header tmux copy-mode can't produce. Same handoff file and popup
-- invocation as the copy-mode `a` / prefix-a bindings in tmux.conf.
vim.keymap.set("x", "<leader>a", function()
  if not vim.env.TMUX then
    vim.notify("annotate: not inside tmux", vim.log.levels.WARN)
    return
  end
  local from, to = vim.fn.getpos("v"), vim.fn.getpos(".")
  local lines = vim.fn.getregion(from, to, { type = vim.fn.mode() })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
  local first, last = math.min(from[2], to[2]), math.max(from[2], to[2])
  local path = vim.fn.expand("%:.")
  if path ~= "" then
    local range = first == last and tostring(first) or first .. "-" .. last
    table.insert(lines, 1, path .. ":" .. range)
  end
  vim.fn.writefile(lines, "/tmp/tmux-annot-sel")
  vim.system({
    "tmux", "display-popup", "-E", "-w", "50%", "-h", "50%", "-x", "R", "-y", "1",
    "-T", "#[align=centre] annotate (:wq send · :cq stash) ",
    vim.fn.expand("~/.config/tmux/scripts/annotate.sh"),
  })
end, { desc = "Send to agent (annotate)" })
