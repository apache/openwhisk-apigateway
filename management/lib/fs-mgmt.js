var logger = require('bunyan').createLogger({
  name: 'fs-mgmt'
});
var fs = require('fs-extra');
var path = require('path');
var url = require('url');

exports.addRoute = function (req) {

  var fileName = [req.namespace, req.route].join('/') + '.conf';
  var dirName = ['/etc/api-gateway/managed_confs', fileName].join('/');
  var conf = fs.readFileSync(path.resolve(__dirname + '/../template.conf'), 'utf8');
  var verbObj = JSON.stringify(req.verb);
  conf = conf.replace(new RegExp('##tempNS##', 'g'), req.namespace).replace('##tempRoute##', req.route)
             .replace('##fullRouteObj##', verbObj);
  try{
    fs.outputFileSync(dirName, conf);
  } catch(e){
    logger.error(e);
  }
};

exports.deleteRoute = function (req) {

  var fileName = [req.namespace, req.route].join('/') + '.conf';
  var dirName = ['/etc/api-gateway/managed_confs', fileName].join('/');

  try {
    fs.removeSync(dirName);
  } catch(e){
    logger.error(e);
  }
};
