#include "mainwindow.h"
#include <QApplication>
#include <QSettings>
#include <QDir>
#include <QCoreApplication>
#include <gfile.h>
#include <unzip.h>
#include <pluginmanager.h>
#include <QDebug>
#include <QLibrary>
#include <lua.hpp>
#include <ghttp.h>
#include <gpath.h>
#include <gstdio.h>
#include <gvfs-native.h>
#include <gui.h>
#include <ginput.h>
#include <gevent.h>
#include <ggeolocation.h>
#include <gtexture.h>
#include <gapplication.h>
#include <gaudio.h>
#include <memory.h>
#include <glog.h>
#include <bytebuffer.h>
#include "constants.cpp"
#include "tabletapplication.h"

static void loadPlugins(){
	QDir dir = QDir(QCoreApplication::applicationDirPath());

    #if defined(Q_OS_MAC)
        dir.cd("../Plugins"); //One dir up from xxx.app/Contents/MacOS
        QStringList files = dir.entryList(QStringList() << "*.dylib");
    #elif defined(Q_OS_LINUX)
        dir.cd("Plugins");
        QStringList files = dir.entryList(QStringList() << "*.so");
    #else
        dir.cd("Plugins");
        QStringList files = dir.entryList(QStringList() << "*.dll");
    #endif

    for(int i = 0; i < files.size(); ++i){
		QString filename = dir.absoluteFilePath(files[i]);
		QLibrary library(filename);
        void* plugin = (void*)library.resolve("g_pluginMain");
		if (plugin)
			PluginManager::instance().registerPlugin((void*(*)(lua_State*, int))plugin);
	}
}

std::vector<std::string> PATH_CommandLine;
int main(int argc, char *argv[]){
    for (int i=0;i<argc;i++)
        PATH_CommandLine.push_back(std::string(argv[i]));
    QCoreApplication::setAttribute(Qt::AA_UseDesktopOpenGL);
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    TabletApplication a(argc, argv);

    QDir dir = QCoreApplication::applicationDirPath();

    #if defined(Q_OS_MAC)
        dir.cdUp();
    #endif

    QFile file(dir.absolutePath()+"/assets/data.bin");
    int vsync=0;
    int fps=60;
    if(file.exists()){
        file.open(QIODevice::ReadOnly);
        QByteArray ba = file.readAll();
        file.close();
        std::vector<char> data(ba.data(), ba.data() + ba.size());
        ByteBuffer buffer(&data[0], data.size());
        std::string ORGANIZATION_NAME;
        std::string ORGANIZATION_DOMAIN;
        std::string DESK_APPLICATION_NAME;
        buffer >> ORGANIZATION_NAME;
        buffer >> ORGANIZATION_DOMAIN;
        buffer >> DESK_APPLICATION_NAME;
        buffer >> vsync;
        buffer >> fps;
        QCoreApplication::setOrganizationName(QString::fromStdString(ORGANIZATION_NAME));
        QCoreApplication::setOrganizationDomain(QString::fromStdString(ORGANIZATION_DOMAIN));
        QCoreApplication::setApplicationName(QString::fromStdString(DESK_APPLICATION_NAME));
    }
    else{
        QCoreApplication::setOrganizationName(Constants::ORGANIZATION_NAME);
        QCoreApplication::setOrganizationDomain(Constants::ORGANIZATION_DOMAIN);
        QCoreApplication::setApplicationName(Constants::DESK_APPLICATION_NAME);
    }

    GLCanvas::EnableVSYNC=vsync;
    QSurfaceFormat formatGL;
	formatGL.setSwapInterval(vsync?(60/fps):0);
	formatGL.setStencilBufferSize(8);
	formatGL.setDepthBufferSize(16);
	formatGL.setSwapBehavior(QSurfaceFormat::DoubleBuffer);
	QSurfaceFormat::setDefaultFormat(formatGL);

	QDir::setCurrent(dir.absolutePath());

    gpath_init();

    gpath_addDrivePrefix(0, "|R|");
    gpath_addDrivePrefix(0, "|r|");
    gpath_addDrivePrefix(1, "|D|");
    gpath_addDrivePrefix(1, "|d|");
    gpath_addDrivePrefix(2, "|T|");
    gpath_addDrivePrefix(2, "|t|");

    gpath_setDriveFlags(0, GPATH_RO | GPATH_REAL);
    gpath_setDriveFlags(1, GPATH_RW | GPATH_REAL);
    gpath_setDriveFlags(2, GPATH_RW | GPATH_REAL);

    gpath_setAbsolutePathFlags(GPATH_RW | GPATH_REAL);

    gpath_setDefaultDrive(0);

    gvfs_init();

    gevent_Init();

    gapplication_init();

    ginput_init();

    ggeolocation_init();

    ghttp_Init();

    gui_init();

    gtexture_init();

    gaudio_Init();

    loadPlugins();

	int result = 0;
	{
		MainWindow w;
        w.show();
		result = a.exec();
	}

    gaudio_Cleanup();

    gtexture_cleanup();

    gui_cleanup();

    ghttp_Cleanup();

    ggeolocation_init();

    ginput_cleanup();

    gapplication_cleanup();

    gevent_Cleanup();

    gvfs_cleanup();

    gpath_cleanup();

	return result;
}
