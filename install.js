const fs = require('fs');
const path = require('path');
const which = require('which');
const {spawn} = require('child_process');

function findBashForWindows() {
    let bash = which.sync('bash', {nothrow: true});

    if (bash)
        return bash;

    let git = which.sync('git', {nothrow: true});

    if (git) {
        bash = path.join(path.dirname(path.dirname(git)), 'usr', 'bin', 'bash.exe');
        if (fs.existsSync(bash))
            return bash;
    } else {
        bash = path.join(process.env.PROGRAMFILES, 'Git', 'usr', 'bin', 'bash.exe');
        if (fs.existsSync(bash))
            return bash;
    }

    console.error('ERROR: Bash was not found. This can be solved by installing Git.')
    console.error("\nGet Git from https://git-scm.com/downloads and try again.");
    process.exit(1);
}

let bash = 'bash';

if (path.sep == '\\') {
    bash = findBashForWindows();
    console.log("Found Bash at", bash);
    process.env.PATH = path.dirname(bash).concat(path.delimiter, process.env.PATH);
}

spawn(bash, [
    path.join(__dirname, 'install.sh')
], {
    stdio: 'inherit'
}).on('exit', function(code) {
    process.exit(code);
});
