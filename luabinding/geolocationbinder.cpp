#if TARGET_OS_TV == 0
#include "geolocationbinder.h"
#include <eventdispatcher.h>
#include <ggeolocation.h>
#include "luautil.h"
#include <gevent.h>

static char key = ' ';

#ifndef abs_index
#define abs_index(L, i) ((i) > 0 || (i) <= LUA_REGISTRYINDEX ? (i) : lua_gettop(L) + (i) + 1)
#endif

static Event::Type LOCATION_UPDATE("locationUpdate");
static Event::Type HEADING_UPDATE("headingUpdate");
static Event::Type ERROR("error");

static lua_State *L = NULL;
class GGGeolocation : public EventDispatcher
{
public:
    GGGeolocation(lua_State */*L*/)
    {
        isUpdatingLocation_ = false;
        isUpdatingHeading_ = false;

        ggeolocation_addCallback(callback_s, this);
    }

    ~GGGeolocation()
    {
        stop();
        ggeolocation_removeCallback(callback_s, this);
    }

    void start()
    {
        startUpdatingLocation();
        startUpdatingHeading();
    }

    void stop()
    {
        stopUpdatingLocation();
        stopUpdatingHeading();
    }

    void startUpdatingLocation()
    {
        if (isUpdatingLocation_)
            return;

        isUpdatingLocation_ = true;

        ggeolocation_startUpdatingLocation();
    }

    void stopUpdatingLocation()
    {
        if (!isUpdatingLocation_)
            return;

        isUpdatingLocation_ = false;

        ggeolocation_stopUpdatingLocation();
    }

    void startUpdatingHeading()
    {
        if (isUpdatingHeading_)
            return;

        isUpdatingHeading_ = true;

        ggeolocation_startUpdatingHeading();
    }

    void stopUpdatingHeading()
    {
        if (!isUpdatingHeading_)
            return;

        isUpdatingHeading_ = false;

        ggeolocation_stopUpdatingHeading();
    }

private:
    static void callback_s(int type, void *event, void *udata)
    {
        static_cast<GGGeolocation*>(udata)->callback(type, event);
    }

    void callback(int type, void *event)
    {
        if (type == GGEOLOCATION_LOCATION_UPDATE_EVENT && !isUpdatingLocation_)
            return;

        if (type == GGEOLOCATION_HEADING_UPDATE_EVENT && !isUpdatingHeading_)
            return;

        if (type == GGEOLOCATION_ERROR_EVENT && !isUpdatingLocation_)
            return;

        if (type == GGEOLOCATION_LOCATION_UPDATE_EVENT && !hasEventListener(LOCATION_UPDATE))
            return;

        if (type == GGEOLOCATION_HEADING_UPDATE_EVENT && !hasEventListener(HEADING_UPDATE))
            return;

        if (type == GGEOLOCATION_ERROR_EVENT && !hasEventListener(ERROR))
            return;

        luaL_rawgetptr(L, LUA_REGISTRYINDEX, &key);
        luaL_rawgetptr(L, -1, this);

        if (lua_isnil(L, -1))
        {
            lua_pop(L, 2);
            return;
        }

        lua_getfield(L, -1, "dispatchEvent");

        lua_pushvalue(L, -2); // create copy of geolocation

        if (type == GGEOLOCATION_LOCATION_UPDATE_EVENT)
        {
            lua_getfield(L, -1, "__updateLocationEvent");

            ggeolocation_LocationUpdateEvent *event2 = (ggeolocation_LocationUpdateEvent*)event;

            lua_pushnumber(L, event2->latitude);
            lua_setfield(L, -2, "latitude");
            lua_pushnumber(L, event2->longitude);
            lua_setfield(L, -2, "longitude");
            lua_pushnumber(L, event2->altitude);
            lua_setfield(L, -2, "altitude");
            if (event2->speed<0)
            	lua_pushnil(L);
            else
            	lua_pushnumber(L, event2->speed);
            lua_setfield(L, -2, "speed");
            if (event2->course<0)
            	lua_pushnil(L);
            else
            	lua_pushnumber(L, event2->course);
            lua_setfield(L, -2, "course");
            lua_pushnumber(L, event2->accuracy);
            lua_setfield(L, -2, "accuracy");
            lua_pushinteger(L, event2->type);
            lua_setfield(L, -2, "source");
        }
        else if (type == GGEOLOCATION_HEADING_UPDATE_EVENT)
        {
            lua_getfield(L, -1, "__updateHeadingEvent");

            ggeolocation_HeadingUpdateEvent *event2 = (ggeolocation_HeadingUpdateEvent*)event;

            lua_pushnumber(L, event2->magneticHeading);
            lua_setfield(L, -2, "magneticHeading");
            lua_pushnumber(L, event2->trueHeading);
            lua_setfield(L, -2, "trueHeading");
            lua_pushnumber(L, event2->magneticX);
            lua_setfield(L, -2, "magneticX");
            lua_pushnumber(L, event2->magneticY);
            lua_setfield(L, -2, "magneticY");
            lua_pushnumber(L, event2->magneticZ);
            lua_setfield(L, -2, "magneticZ");
        }
        else if (type == GGEOLOCATION_ERROR_EVENT)
        {
            lua_getfield(L, -1, "__errorEvent");
        }

        lua_call(L, 2, 0); // call geolocation:dispatchEvent(event)

        lua_pop(L, 2);
    }

    bool isUpdatingLocation_;
    bool isUpdatingHeading_;
    g_id callbackid_;
};

GeolocationBinder::GeolocationBinder(lua_State *L)
{
	::L=L;
    Binder binder(L);

    static const luaL_Reg functionList[] = {
        {"isAvailable", isAvailable},
        {"isHeadingAvailable", isHeadingAvailable},
        {"setAccuracy", setAccuracy},
        {"getAccuracy", getAccuracy},
        {"setThreshold", setThreshold},
        {"getThreshold", getThreshold},
        {"start", start},
        {"stop", stop},
        {"startUpdatingLocation", startUpdatingLocation},
        {"stopUpdatingLocation", stopUpdatingLocation},
        {"startUpdatingHeading", startUpdatingHeading},
        {"stopUpdatingHeading", stopUpdatingHeading},
        {NULL, NULL},
    };

    binder.createClass("Geolocation", "EventDispatcher", create, destruct, functionList);

    lua_getglobal(L, "Event");
    lua_pushstring(L, LOCATION_UPDATE.type());
    lua_setfield(L, -2, "LOCATION_UPDATE");
    lua_pushstring(L, HEADING_UPDATE.type());
    lua_setfield(L, -2, "HEADING_UPDATE");
    lua_pop(L, 1);

    luaL_newweaktable(L);
    luaL_rawsetptr(L, LUA_REGISTRYINDEX, &key);
}


int GeolocationBinder::create(lua_State* L)
{
    Binder binder(L);

    GGGeolocation *geolocation = new GGGeolocation(L);
    binder.pushInstance("Geolocation", geolocation);

    lua_getglobal(L, "Event");

    lua_getfield(L, -1, "new");
    lua_remove(L, -2);				// remove global "Event"

    lua_pushvalue(L, -1);	// duplicate Event.new
    lua_pushstring(L, LOCATION_UPDATE.type());
    lua_call(L, 1, 1); // call Event.new
    lua_setfield(L, -3, "__updateLocationEvent");

    lua_pushvalue(L, -1);	// duplicate Event.new
    lua_pushstring(L, HEADING_UPDATE.type());
    lua_call(L, 1, 1); // call Event.new
    lua_setfield(L, -3, "__updateHeadingEvent");

    lua_pushvalue(L, -1);	// duplicate Event.new
    lua_pushstring(L, ERROR.type());
    lua_call(L, 1, 1); // call Event.new
    lua_setfield(L, -3, "__errorEvent");

    lua_pop(L, 1);		// pop Event.new

    luaL_rawgetptr(L, LUA_REGISTRYINDEX, &key);
    lua_pushvalue(L, -2);
    luaL_rawsetptr(L, -2, geolocation);
    lua_pop(L, 1);

    return 1;
}

int GeolocationBinder::destruct(void *p)
{
	void *ptr = GIDEROS_DTOR_UDATA(p);
    GGGeolocation *geolocation = static_cast<GGGeolocation*>(ptr);
    geolocation->unref();

    return 0;
}

int GeolocationBinder::isAvailable(lua_State* L)
{
    Binder binder(L);

    lua_pushboolean(L, ggeolocation_isAvailable());

    return 1;
}

int GeolocationBinder::isHeadingAvailable(lua_State* L)
{
    Binder binder(L);

    lua_pushboolean(L, ggeolocation_isHeadingAvailable());

    return 1;
}

int GeolocationBinder::setAccuracy(lua_State* L)
{
    Binder binder(L);

    ggeolocation_setAccuracy(luaL_checknumber(L, 2));

    return 0;
}

int GeolocationBinder::getAccuracy(lua_State* L)
{
    Binder binder(L);

    lua_pushnumber(L, ggeolocation_getAccuracy());

    return 1;
}


int GeolocationBinder::setThreshold(lua_State* L)
{
    Binder binder(L);

    ggeolocation_setThreshold(luaL_checknumber(L, 2));

    return 0;
}

int GeolocationBinder::getThreshold(lua_State* L)
{
    Binder binder(L);

    lua_pushnumber(L, ggeolocation_getThreshold());

    return 1;
}


int GeolocationBinder::start(lua_State* L)
{
    Binder binder(L);
    GGGeolocation* geolocation = static_cast<GGGeolocation*>(binder.getInstance("Geolocation", 1));

    geolocation->start();

    return 0;
}

int GeolocationBinder::stop(lua_State* L)
{
    Binder binder(L);
    GGGeolocation* geolocation = static_cast<GGGeolocation*>(binder.getInstance("Geolocation", 1));

    geolocation->stop();

    return 0;
}

int GeolocationBinder::startUpdatingLocation(lua_State* L)
{
    Binder binder(L);
    GGGeolocation* geolocation = static_cast<GGGeolocation*>(binder.getInstance("Geolocation", 1));

    geolocation->startUpdatingLocation();

    return 0;
}
int GeolocationBinder::stopUpdatingLocation(lua_State* L)
{
    Binder binder(L);
    GGGeolocation* geolocation = static_cast<GGGeolocation*>(binder.getInstance("Geolocation", 1));

    geolocation->stopUpdatingLocation();

    return 0;
}

int GeolocationBinder::startUpdatingHeading(lua_State* L)
{
    Binder binder(L);
    GGGeolocation* geolocation = static_cast<GGGeolocation*>(binder.getInstance("Geolocation", 1));

    geolocation->startUpdatingHeading();

    return 0;
}

int GeolocationBinder::stopUpdatingHeading(lua_State* L)
{
    Binder binder(L);
    GGGeolocation* geolocation = static_cast<GGGeolocation*>(binder.getInstance("Geolocation", 1));

    geolocation->stopUpdatingHeading();

    return 0;
}
#endif
