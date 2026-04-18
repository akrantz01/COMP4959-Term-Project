const plugin = require("tailwindcss/plugin");
const fs = require("fs");
const path = require("path");

module.exports = plugin(function ({ matchComponents, theme }) {
  const iconsDir = path.join(__dirname, "../../deps/fontawesome/svgs-full");
  const families = [
    ["fas", "solid"],
    ["far", "regular"],
    ["fab", "brands"],
  ];

  const iconFor = ({ name, fullPath }) => {
    const content = fs
      .readFileSync(fullPath)
      .toString()
      .replace(/\r?\n|\r/g, "");

    return {
      [`--fa-${name}`]: `url('data:image/svg+xml;utf8,${encodeURIComponent(content)}')`,
      "-webkit-mask": `var(--fa-${name})`,
      mask: `var(--fa-${name})`,
      "mask-repeat": "no-repeat",
      "mask-size": "contain",
      "mask-position": "center",
      "background-color": "currentColor",
      "vertical-align": "middle",
      display: "inline-block",
      width: theme("spacing.6"),
      height: theme("spacing.6"),
    };
  };

  families.forEach(([prefix, dir]) => {
    const dirPath = path.join(iconsDir, dir);
    if (!fs.existsSync(dirPath)) return;

    const values = {};
    fs.readdirSync(dirPath).forEach((file) => {
      if (!file.endsWith(".svg")) return;
      const name = path.basename(file, ".svg");
      values[name] = {
        name: `${dir}-${name}`,
        fullPath: path.join(dirPath, file),
      };
    });

    matchComponents({ [prefix]: iconFor }, { values });
  });
});
