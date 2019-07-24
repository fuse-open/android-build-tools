const fs = require('fs');
const path = require('path');
const EOL = require('os').EOL;

const obj = {};
const args = process.argv.slice(2);
const filename = path.join(path.sep == '\\'
                                ? process.env.USERPROFILE
                                : process.env.HOME,
                            '.unoconfig');

for (let i = 0; i < args.length; i++) {
    const colon = args[i].indexOf(':');
    obj[args[i].substring(0, colon)] = args[i].substring(colon + 1);
}

const lines = fs.existsSync(filename)
    ? fs.readFileSync(filename, "utf8").split(/\n|\r\n/)
    : [];

for (key in obj) {
    // Remove old instances of ${key}
    for (let i = 0; i < lines.length; i++)
        if (lines[i] && lines[i].startsWith(key + ':'))
            lines.splice(i--);

    // Add new ${key}
    if (obj[key] && obj[key].length)
        if (obj[key].indexOf('\\') != -1)
            lines.push(`${key}: \`${obj[key]}\``);
        else if (obj[key].indexOf(' ') != -1 ||
                 obj[key].indexOf(':') != -1)
            lines.push(`${key}: "${obj[key]}"`);
        else
            lines.push(`${key}: ${obj[key]}`);
}

fs.writeFileSync(filename, lines.join(EOL).trim() + EOL);

// Fallback (TODO: remove after Uno v1.13)
fs.writeFileSync('.unoconfig', `require \`${filename}\`${EOL}`);
