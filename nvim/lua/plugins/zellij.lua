return {
  "swaits/zellij-nav.nvim",
  lazy = true,
  event = "VeryLazy",
  keys = {
    { "<c-h>", "<cmd>ZellijNavigateLeftTab<cr>",  silent = true, desc = "Navigate left (zellij-aware)" },
    { "<c-j>", "<cmd>ZellijNavigateDown<cr>",     silent = true, desc = "Navigate down (zellij-aware)" },
    { "<c-k>", "<cmd>ZellijNavigateUp<cr>",       silent = true, desc = "Navigate up (zellij-aware)" },
    { "<c-l>", "<cmd>ZellijNavigateRightTab<cr>", silent = true, desc = "Navigate right (zellij-aware)" },
  },
  opts = {},
}
