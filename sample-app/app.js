const express = require('express');
const app = express();
const chalk = require('chalk');
const morgan = require('morgan');
const os = require('os');
const checkDiskSpace = require('check-disk-space').default
const fs = require('fs')


app.use(morgan('combined'));

app.use(express.json());

app.get('/', (req, res) => {
    res.send("Hi :) greeting from Collins");
});


app.get('/readjson', (req, res) => {
    readLocalJsonFile(res);
})

app.post('/updatejson', (req, res) => {
    
    const update = req.body.update;
    changeJsonValue(update, res)
})

app.get('/serverload', (req, res) => {

    getAvailableDiskSpaceOnMachine(res);
})

app.listen(3000, () => {
    console.log(`listening on port ${chalk.green('3000')}`);
});

function readLocalJsonFile(res){
    fs.readFile('./data.json', 'utf-8', (err, json) => {
        if (err) {
            res.send('unable to read data.json')
        } else {
            try {
                console.log(json);
                const jsonObject = JSON.parse(json);
                res.send(`${jsonObject.tech.return_value}`);
            } catch (err) {
                res.send('unable to read data.json')
            }
        }
    });
}

function updateJsonFile(jsonObject, res){
    fs.writeFile('./data.json', JSON.stringify(jsonObject), err => {
        if(err){
            res.send(`unable to write make update`);
        }else{
            res.send(`file updated to ${jsonObject.tech.return_value}`);
        }
    })
}

function changeJsonValue(update, res){
    fs.readFile('./data.json', 'utf-8', (err, json) => {
        if (err) {
            res.send('unable to read data.json')
        } else {
            try {
                const jsonObject = JSON.parse(json);
                jsonObject.tech.return_value = update
                console.log(jsonObject);
                updateJsonFile(jsonObject,res);
            } catch (err) {
                res.send('unable to read data.json')
            }
        }
    });
}

function getAverageLoad() {
    let averageLoad = os.loadavg();
    return `Average Load in 1 min: ${averageLoad[0]} \n
    Average Load in 5 min: ${averageLoad[1]} \n
    Average Load in 15 min: ${averageLoad[2]} `
}

const convertBytes = function (bytes) {
    const sizes = ["Bytes", "KB", "MB", "GB", "TB"]

    if (bytes == 0) {
        return "n/a"
    }

    const i = parseInt(Math.floor(Math.log(bytes) / Math.log(1024)))

    if (i == 0) {
        return bytes + " " + sizes[i]
    }

    return (bytes / Math.pow(1024, i)).toFixed(1) + " " + sizes[i]
}

function getAvailableDiskSpaceOnMachine(res) {
    console.log("getAvailableDiskSpaceOnMachine")
    const averageLoad = getAverageLoad();
    const type = os.type();
    switch (type) {
        case 'Darwin':
            getAvailableDiskSpaceOnLinuxOrMac(res);
            break;

        case 'Linux':
            getAvailableDiskSpaceOnLinuxOrMac(res);
            break;

        case 'Windows_NT':
            getAvailableDiskSpaceOnWindows(res);
            break;

        default:
            console.log("getAvailableDiskSpaceOnMachine default")
            diskSpaceInfo = "Operating system expected Mac, Linux and Windows";
            res.send(`${averageLoad}\n${diskSpaceInfo}`);

    }

}

function getAvailableDiskSpaceOnLinuxOrMac(res) {
    console.log("getAvailableDiskSpaceOnLinuxOrMac")
    const averageLoad = getAverageLoad();
    let diskSpaceInfo = ""

    checkDiskSpace('/').then((diskSpace) => {

        diskSpaceInfo = `FreeSize : ${convertBytes(diskSpace.free)} \nSize: ${convertBytes(diskSpace.size)}`

        res.send(`${averageLoad}\n${diskSpaceInfo}`);


    }).catch(err => {
        res.send(`${averageLoad}\n unable to get disk size`);
    });
}

function getAvailableDiskSpaceOnWindows() {
    const averageLoad = getAverageLoad();
    let diskSpaceInfo = ""

    checkDiskSpace('C:').then((diskSpace) => {
        diskSpaceInfo = `FreeSize : ${convertBytes(diskSpace.free)} \nSize: ${convertBytes(diskSpace.size)}`

        res.send(`${averageLoad}\n${diskSpaceInfo}`);
    }).catch(err => {
        res.send(`${averageLoad}\n unable to get disk size`);
    });
}