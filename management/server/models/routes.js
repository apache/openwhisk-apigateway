var logger = require('bunyan').createLogger({
    name: 'models/routes'
});
var fsMgmt = require('../../lib/fs-mgmt');
var btoa = require('btoa');
var url = require('url');

module.exports = function (Routes) {

    var isStatic = true;
    Routes.disableRemoteMethod('count', isStatic);
    Routes.disableRemoteMethod('exists', isStatic);
    Routes.disableRemoteMethod('findOne', isStatic);
    Routes.disableRemoteMethod('updateAll', isStatic);
    Routes.disableRemoteMethod('replaceById', isStatic);
    Routes.disableRemoteMethod('replaceOrCreate', isStatic);
    Routes.disableRemoteMethod('createChangeStream', isStatic);
    Routes.disableRemoteMethod('deleteById', isStatic);
    Routes.disableRemoteMethod('create', isStatic);
    Routes.disableRemoteMethod('upsert', isStatic);
    Routes.disableRemoteMethod('updateAll', isStatic);

//---------------Add Route---------------

    Routes.remoteMethod('addRoute', {
        http: {path: '/', verb: 'put', status: 201},
        accepts: [
            {arg: 'namespace', type: 'string'},
            {arg: 'route', type: 'string'},
            {arg: 'verb', type: 'string'},
            {arg: 'targetHost', type: 'string'},
            {arg: 'targetPath', type: 'string'},
            {arg: 'requestMapping', type: 'array'}],
        returns: {
            arg: 'managed_url',
            type: 'string'
        }
    });

    Routes.addRoute = function (namespace, route, verb, targetHost, targetPath, requestMapping, cb) {
        try {
            if (!verb) {
                throw {name: "Error", status: 400, message: "Incomplete request. Must specify the verb to operate on"};
            }
            verb = verb.toUpperCase();
            if (verb !== "GET" && verb !== "PUT" && verb !== "POST" && verb !== "DELETE") {
                throw {name: "Error", status: 400, message: "Invalid request. Verb type not supported."};
            }
            if (!namespace) {
                throw {name: "Error", status: 400, message: "Incomplete request. Must specify the namespace to operate on"};
            }
            if (!route) {
                throw {name: "Error", status: 400, message: "Incomplete request. Must specify the route to operate on"};
            }
            if (!targetHost) {
                throw {name: "Error", status: 400, message: "Incomplete request. Must specify a target Host to route to"};
            }
            if (!targetPath) {
                throw {name: "Error", status: 400, message: "Incomplete request. Must specify a target Path to route to"};
            }
            Routes.findOne({where: {namespace: namespace, route: route}})
            .then(function (doc) {
                if (doc) {
                    //doc exists
                    if (doc.verb[verb]) {
                        //update verb
                        doc.verb[verb].targetHost = targetHost;
                        doc.verb[verb].targetPath = targetPath;
                        if (requestMapping) {
                            //has a mapping
                            doc.verb[verb].reqMapping = [];
                            for (var i = 0; i < requestMapping.length; i++) {
                                var t = ParamMapping(requestMapping[i]);
                                if(t.error) {
                                   return cb(t.error);
                                }
                                doc.verb[verb].reqMapping.push(t);
                            }
                        }
                    } else {
                        //add new verb
                        doc.verb[verb] = {
                            targetHost : targetHost,
                            targetPath : targetPath
                        };
                        if (requestMapping) {
                            //has a mapping
                            doc.verb[verb].reqMapping = [];
                            for (var i = 0; i < requestMapping.length; i++) {
                                var t = ParamMapping(requestMapping[i]);
                                if(t.error) {
                                   return cb(t.error);
                                }
                                doc.verb[verb].reqMapping.push(t);
                            }
                        }
                    }
                } else {
                    //create doc, with first verb
                    doc = {
                        namespace: namespace,
                        route: route,
                        verb: {}
                    };
                    doc.verb[verb] = {
                        targetHost : targetHost,
                        targetPath : targetPath
                    };
                    if (requestMapping) {
                        //has a mapping
                        doc.verb[verb].reqMapping = [];
                        for (var i = 0; i < requestMapping.length; i++) {
                            var t = ParamMapping(requestMapping[i]);
                            if(t.error) {
                               return cb(t.error);
                            }
                            doc.verb[verb].reqMapping.push(t);
                        }
                    }
                }
                Routes.upsert(doc, function () {
                    logger.info('doc = ', doc);
                    fsMgmt.addRoute(doc);
                    cb(null);
                });
            });
        }
        catch (e) {
            cb(e);
        }
    };

//---------------Delete Route---------------

    Routes.remoteMethod('deleteByRoute', {
        http: {path: '/', verb: 'delete', status: 204},
        accepts: [
            {arg: 'route', type: 'string'},
            {arg: 'namespace', type: 'string'},
            {arg: 'verb', type: 'string'}]
    });

    Routes.deleteByRoute = function (route, namespace, verb, cb) {
        try {
            if (!namespace) {
                throw {name: "Error", status: 400, message: "Incomplete request. Must specify the namespace to operate on"};
            }
            if (!route) {
                throw {name: "Error", status: 400, message: "Incomplete request. Must specify the route to operate on"};
            }
            Routes.findOne({where: {namespace: namespace} && {route: route}})
            .then(function (doc) {
                if (doc && verb === undefined) {
                    Routes.deleteById(doc.id);
                    fsMgmt.deleteRoute(doc);
                } else {
                    delete doc.verb[verb];
                    if (JSON.stringify(doc.verb) === JSON.stringify({})) {
                        Routes.deleteById(doc.id);
                        fsMgmt.deleteRoute(doc);
                    } else {
                        Routes.upsert(doc, function () {
                            fsMgmt.addRoute(doc);
                        });
                    }
                }
            });
            //Routes.find({include: {namespace: namespace,route: route}}, function(temp) {
        }
        catch (e) {
            cb(e);
        }
        cb(null);
    };

  Routes.afterRemote('addRoute', function(ctx, modelInstance, next){
    console.log('after add route');
    var args = ctx.args;
    console.log(args);
    var managedUrl = {
      protocol: 'https',
      host: ctx.req.hostname,
      pathname: '/gateway/api/' + args.namespace + args.route
    };
    console.log(managedUrl);
    ctx.result.managed_url = url.format(managedUrl);
    next();
  })
};

//---------------Save Param Mapping---------------
function ParamMapping(mapping) {
    var temp = {};
    var error = {};
    if (!mapping.action) {
        logger.info("Throw error, no action given");
        error.error = {name: "Error", status: 400, message: "Incomplete mapping. Must specify a mapping action to perform on parameters"};
        return error;
    }
    if (mapping.action !== 'remove' &&
        mapping.action !== 'insert' &&
        mapping.action !== 'transform') {
        error.error = {name: "Error", status: 400, message: "Invalid mapping action. Must be: remove, insert, or transform"};
        return error;
    }
    temp.action = mapping.action;
    temp.from = {};
    if (mapping.action === 'insert' && mapping.from.value) {
        temp.from.value = mapping.from.value;
    } else {
        if (mapping.from.name) {
            temp.from.name = mapping.from.name;
        } else {
            error.error = {name: "Error", status: 400, message: "Incomplete mapping. Must specify the name of parameter to operate on"};
            return error;
        }
        if (mapping.from.location) {
            temp.from.location = mapping.from.location;
        } else {
            error.error = {name: "Error", status: 400, message: "Incomplete mapping. Must specify the location of parameter to operate on"};
            return error;
        }
    }
    if (mapping.action !== 'remove') {
        temp.to = {};
        if (mapping.to.name) {
            temp.to.name = mapping.to.name;
        } else {
            error.error = {name: "Error", status: 400, message: "Incomplete mapping. Must specify the name of parameter to map to"};
            return error;
        }
        if (mapping.to.location) {
            temp.to.location = mapping.to.location;
        } else {
            error.error = {name: "Error", status: 400, message: "Incomplete mapping. Must specify the location of parameter to map to"};
            return error;
        }
    }
    return temp;
}
