#include <stdio.h>
#include <string>
#include <map>
#include <ghttp-linux.h>
#include <pthread.h>
#include <curl/curl.h>
#include <algorithm>
#include <cctype>
#include <locale>

//#define CURL_DEBUG
static bool sslErrorsIgnore=false;
static std::string colon=": ";
static std::string capath;

struct NetworkReply
{
  g_id gid;
  gevent_Callback callback;
  void *udata;
  std::string url;
  pthread_t tid;
  void *data;
  size_t size;
  std::vector<std::string> header;
  std::vector<std::pair<std::string,std::string>> rspheader;
  bool streaming;
};

struct MemoryStruct {
  char *memory;
  size_t size;
  struct NetworkReply *reply;
};

static pthread_mutex_t mutexmap;

static std::map<g_id, NetworkReply> map_;

// ######################################################################

int progress_callback(void *clientp,   double dltotal,   double dlnow,   double ultotal,   double ulnow)
{
  NetworkReply *reply2 = (NetworkReply*)clientp;
  
  ghttp_ProgressEvent* event = (ghttp_ProgressEvent*)malloc(sizeof(ghttp_ProgressEvent));
  event->bytesLoaded = dlnow > ulnow ? dlnow : ulnow;
  event->bytesTotal = dltotal > ultotal ? dltotal : ultotal;
  event->chunk=NULL;
  event->chunkSize=0;
  
  gevent_EnqueueEvent(reply2->gid, reply2->callback, GHTTP_PROGRESS_EVENT, event, 1, reply2->udata);
  
  return 0;
}

//######################################################################

static size_t
WriteMemoryCallback(void *contents, size_t size, size_t nmemb, void *userp)
{
  size_t realsize = size * nmemb;
  MemoryStruct *mem = (MemoryStruct *)userp;
  NetworkReply *reply2 = mem->reply;

  if (reply2->streaming) {
  ghttp_ProgressEvent* event = (ghttp_ProgressEvent*)malloc(sizeof(ghttp_ProgressEvent)+realsize);
  event->bytesLoaded = 0;
  event->bytesTotal = 0;
  event->chunk=event+1;
  event->chunkSize=realsize;
  memcpy(event->chunk,contents,realsize);

  gevent_EnqueueEvent(reply2->gid, reply2->callback, GHTTP_PROGRESS_EVENT, event, 1, reply2->udata);
  } else {
	mem->memory = (char*)realloc(mem->memory, mem->size + realsize + 1);
	if(mem->memory == NULL) {
	/* out of memory! */
	printf("HTTP: not enough memory (realloc returned NULL)\n");
	return 0;
	}

	memcpy(&(mem->memory[mem->size]), contents, realsize);
	mem->size += realsize;
	mem->memory[mem->size] = 0;
  }
  return realsize;
}

// trim from start (in place)
static inline void ltrim(std::string &s) {
    s.erase(s.begin(), std::find_if(s.begin(), s.end(), [](unsigned char ch) {
        return !std::isspace(ch);
    }));
}

// trim from end (in place)
static inline void rtrim(std::string &s) {
    s.erase(std::find_if(s.rbegin(), s.rend(), [](unsigned char ch) {
        return !std::isspace(ch);
    }).base(), s.end());
}

// trim from both ends (in place)
static inline void trim(std::string &s) {
    ltrim(s);
    rtrim(s);
}

static size_t
HeaderCallback(void *contents, size_t size, size_t nmemb, void *userp)
{
  size_t realsize = size * nmemb;
  MemoryStruct *mem = (MemoryStruct *)userp;
  NetworkReply *reply2 = mem->reply;
  char *hdr=(char *)contents;
  int colon=0;
  for (;(colon<nmemb)&&(hdr[colon]!=':');colon++);
  if (colon<nmemb) {
	  int rs=colon+1;
	  for (;(rs<nmemb)&&(hdr[rs]==' ');rs++);
	  std::string key(hdr,colon);
	  std::string val(hdr+rs,nmemb-rs);
	  trim(key);
	  trim(val);
	  reply2->rspheader.push_back(std::pair<std::string,std::string>(key,val));
  }

  return nmemb;
}

//######################################################################

static size_t
ReadMemoryCallback(void *contents, size_t size, size_t nmemb, void *userp)
{
  size_t realsize = size * nmemb;
  MemoryStruct *mem = (MemoryStruct *)userp;

  size_t copysize;

  if (realsize > mem->size)
    copysize=mem->size;
  else
    copysize=realsize;

  memcpy(contents,mem->memory,copysize);
  mem->memory += copysize;
  mem->size -= copysize;

  //  printf("ReadMemoryCallback %d\n",copysize);

  return copysize;
}

// ######################################################################

static void *post_one(void *ptr)        // thread
{
  CURL *curl;
  CURLcode res;

  NetworkReply *reply2 = (NetworkReply*)ptr;

  MemoryStruct chunk;  // for the return message if any

  chunk.memory = (char*)malloc(1);
  chunk.memory[0]='\0';
  chunk.size = 0;
  chunk.reply=reply2;

  curl = curl_easy_init();
#ifdef CURL_DEBUG  
  curl_easy_setopt(curl, CURLOPT_VERBOSE, 1L);
#endif

  struct curl_slist *headers=NULL;

  for (int i=0; i<reply2->header.size(); i++){
    headers = curl_slist_append(headers, reply2->header[i].c_str());
    //printf("header %p %s\n",headers,reply2->header[i].c_str());
  }
  curl_easy_setopt(curl, CURLOPT_CAINFO, capath.c_str());

  curl_easy_setopt(curl, CURLOPT_URL, reply2->url.c_str());
  //  curl_easy_setopt(curl, CURLOPT_UPLOAD, 1L);

  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteMemoryCallback);
  curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, HeaderCallback);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);
  curl_easy_setopt(curl, CURLOPT_HEADERDATA, (void *)&chunk);

  /* post binary data */
  curl_easy_setopt(curl, CURLOPT_POSTFIELDS, reply2->data);
 
  /* set the size of the postfields data */
  curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, reply2->size);
  
  /* pass our list of custom made headers */
  curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

  if (sslErrorsIgnore)
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);                // ignore SSL errors
 
  res=curl_easy_perform(curl); /* post away! */


  if(res != CURLE_OK){
	curl_easy_cleanup(curl);
	ghttp_ErrorEvent *event = (ghttp_ErrorEvent*)gevent_CreateEventStruct1(
			                                           sizeof(ghttp_ErrorEvent),
			                                        offsetof(ghttp_ErrorEvent, error), NULL);
    gevent_EnqueueEvent(reply2->gid, reply2->callback, GHTTP_ERROR_EVENT, event, 1, reply2->udata);
    fprintf(stderr, "curl_easy_perform() failed in post_one: %s\n",curl_easy_strerror(res));
  }
  else {
	  size_t hdrSize=0;
	  size_t hdrCount=reply2->rspheader.size();
	  for (auto it=reply2->rspheader.begin();it!=reply2->rspheader.end();it++)
		  hdrSize+=2+it->first.size()+it->second.size();
      ghttp_ResponseEvent *event = (ghttp_ResponseEvent*)malloc(sizeof(ghttp_ResponseEvent)  + sizeof(ghttp_Header)*hdrCount + chunk.size + hdrSize);
	  event->data = (char*)event + sizeof(ghttp_ResponseEvent) + sizeof(ghttp_Header)*hdrCount;
	  int hdrn=0;
	  char *hdrData=(char *)(event->data)+chunk.size;
	  for (auto h=reply2->rspheader.begin();h!=reply2->rspheader.end();h++)
      {
          int ds=h->first.size();
          memcpy(hdrData,h->first.c_str(),ds);
	 	  event->headers[hdrn].name=hdrData;
      	  hdrData+=ds;
      	  *(hdrData++)=0;
          ds=h->second.size();
          memcpy(hdrData,h->second.c_str(),ds);
	 	  event->headers[hdrn].value=hdrData;
      	  hdrData+=ds;
      	  *(hdrData++)=0;
		 hdrn++;
      }
	  event->headers[hdrn].name=NULL;
	  event->headers[hdrn].value=NULL;

    if (reply2->streaming) {
    	event->size=0;
    }
    else {
		memcpy(event->data, chunk.memory, chunk.size);
		event->size = chunk.size;
    }
    long response_code;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);
    event->httpStatusCode = response_code;

    curl_easy_cleanup(curl);

    gevent_EnqueueEvent(reply2->gid, reply2->callback, GHTTP_RESPONSE_EVENT, event, 1, reply2->udata);
  }

  free(chunk.memory);
  curl_slist_free_all(headers); /* free the header list */

  pthread_mutex_lock (&mutexmap);
  map_.erase(reply2->gid);
  pthread_mutex_unlock (&mutexmap);

  free(reply2->data);

  return NULL;
}

//######################################################################

static void *put_one_url(void *ptr)     // thread
{
  CURL *curl;
  CURLcode res;

  NetworkReply *reply2 = (NetworkReply*)ptr;

  struct curl_slist *headers=NULL;

  for (int i=0; i<reply2->header.size(); i++){
    headers = curl_slist_append(headers, reply2->header[i].c_str());
    //printf("header %p %s\n",headers,reply2->header[i].c_str());
  }

  MemoryStruct chunk;

  chunk.memory=(char*)reply2->data;       // start of the remaining data
  chunk.size=reply2->size;         // size of the remaining data

  MemoryStruct chunkRet;  // for the return message if any

  chunkRet.memory = (char*)malloc(1);
  chunkRet.memory[0]='\0';
  chunkRet.size = 0;
  chunkRet.reply=reply2;

  printf("put_one_url: %s\n",reply2->url.c_str());

  curl=curl_easy_init();
#ifdef CURL_DEBUG  
  curl_easy_setopt(curl, CURLOPT_VERBOSE, 1L);
#endif
  /* pass our list of custom made headers */
  curl_easy_setopt(curl, CURLOPT_CAINFO, capath.c_str());
  curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteMemoryCallback);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunkRet);
  curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, HeaderCallback);
  curl_easy_setopt(curl, CURLOPT_HEADERDATA, (void *)&chunk);

  curl_easy_setopt(curl, CURLOPT_URL, reply2->url.c_str());
  curl_easy_setopt(curl, CURLOPT_READFUNCTION, ReadMemoryCallback);
  curl_easy_setopt(curl, CURLOPT_READDATA, (void *)&chunk);
  curl_easy_setopt(curl, CURLOPT_UPLOAD, 1L);

  if (sslErrorsIgnore)
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);                // ignore SSL errors

  res = curl_easy_perform(curl);

  if(res != CURLE_OK){
    curl_easy_cleanup(curl);
	ghttp_ErrorEvent *event = (ghttp_ErrorEvent*)gevent_CreateEventStruct1(
			                                           sizeof(ghttp_ErrorEvent),
			                                        offsetof(ghttp_ErrorEvent, error), NULL);
    gevent_EnqueueEvent(reply2->gid, reply2->callback, GHTTP_ERROR_EVENT, event, 1, reply2->udata);
    fprintf(stderr, "curl_easy_perform() failed in put_one: %s\n",curl_easy_strerror(res));
  }
  else {
	  size_t hdrSize=0;
	  size_t hdrCount=reply2->rspheader.size();
	  for (auto it=reply2->rspheader.begin();it!=reply2->rspheader.end();it++)
		  hdrSize+=2+it->first.size()+it->second.size();
      ghttp_ResponseEvent *event = (ghttp_ResponseEvent*)malloc(sizeof(ghttp_ResponseEvent)  + sizeof(ghttp_Header)*hdrCount + chunkRet.size + hdrSize);
	  event->data = (char*)event + sizeof(ghttp_ResponseEvent) + sizeof(ghttp_Header)*hdrCount;
	  int hdrn=0;
	  char *hdrData=(char *)(event->data)+chunkRet.size;
	  for (auto h=reply2->rspheader.begin();h!=reply2->rspheader.end();h++)
      {
          int ds=h->first.size();
          memcpy(hdrData,h->first.c_str(),ds);
	 	  event->headers[hdrn].name=hdrData;
      	  hdrData+=ds;
      	  *(hdrData++)=0;
          ds=h->second.size();
          memcpy(hdrData,h->second.c_str(),ds);
	 	  event->headers[hdrn].value=hdrData;
      	  hdrData+=ds;
      	  *(hdrData++)=0;
		 hdrn++;
      }
	  event->headers[hdrn].name=NULL;
	  event->headers[hdrn].value=NULL;

    if (reply2->streaming) {
    	event->size=0;
    }
    else {
		memcpy(event->data, chunkRet.memory, chunkRet.size);
		event->size = chunkRet.size;
    }

    long response_code;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);
    event->httpStatusCode = response_code;
    curl_easy_cleanup(curl);

    gevent_EnqueueEvent(reply2->gid, reply2->callback, GHTTP_RESPONSE_EVENT, event, 1, reply2->udata);
  }

  free(chunkRet.memory);
  curl_slist_free_all(headers); /* free the header list */

  pthread_mutex_lock (&mutexmap);
  map_.erase(reply2->gid);
  pthread_mutex_unlock (&mutexmap);

  free(reply2->data);

  return NULL;
}

//######################################################################

static void *get_one_url(void *ptr)          // thread
{
  CURL *curl;
  CURLcode res;

  NetworkReply *reply2 = (NetworkReply*)ptr;

  struct curl_slist *headers=NULL;

  for (int i=0; i<reply2->header.size(); i++){
    headers = curl_slist_append(headers, reply2->header[i].c_str());
    //printf("header %p %s\n",headers,reply2->header[i].c_str());
  }

  MemoryStruct chunk;

  chunk.memory = (char*)malloc(1);
  chunk.memory[0]='\0';
  chunk.size = 0;
  chunk.reply=reply2;
  
  //printf("Processing: %s\n",reply2->url.c_str());

  curl = curl_easy_init();
#ifdef CURL_DEBUG  
  curl_easy_setopt(curl, CURLOPT_VERBOSE, 1L);
#endif

  curl_easy_setopt(curl, CURLOPT_CAINFO, capath.c_str());
  /* pass our list of custom made headers */
  curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

  curl_easy_setopt(curl, CURLOPT_URL, reply2->url.c_str());
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteMemoryCallback);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);
  curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, HeaderCallback);
  curl_easy_setopt(curl, CURLOPT_HEADERDATA, (void *)&chunk);
  if (!reply2->streaming)
	  curl_easy_setopt(curl, CURLOPT_PROGRESSFUNCTION, progress_callback);
  curl_easy_setopt(curl, CURLOPT_PROGRESSDATA, ptr);

  if (sslErrorsIgnore)
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 0L);                // ignore SSL errors

  res = curl_easy_perform(curl);

  if(res != CURLE_OK){
	  curl_easy_cleanup(curl);
		ghttp_ErrorEvent *event = (ghttp_ErrorEvent*)gevent_CreateEventStruct1(
				                                           sizeof(ghttp_ErrorEvent),
				                                        offsetof(ghttp_ErrorEvent, error), NULL);
    gevent_EnqueueEvent(reply2->gid, reply2->callback, GHTTP_ERROR_EVENT, event, 1, reply2->udata);
    fprintf(stderr, "curl_easy_perform() failed in get_one: %s\n",curl_easy_strerror(res));
  }
  else {
	  size_t hdrSize=0;
	  size_t hdrCount=reply2->rspheader.size();
	  for (auto it=reply2->rspheader.begin();it!=reply2->rspheader.end();it++)
		  hdrSize+=2+it->first.size()+it->second.size();
      ghttp_ResponseEvent *event = (ghttp_ResponseEvent*)malloc(sizeof(ghttp_ResponseEvent)  + sizeof(ghttp_Header)*hdrCount + chunk.size + hdrSize);
	  event->data = (char*)event + sizeof(ghttp_ResponseEvent) + sizeof(ghttp_Header)*hdrCount;
	  int hdrn=0;
	  char *hdrData=(char *)(event->data)+chunk.size;
	  for (auto h=reply2->rspheader.begin();h!=reply2->rspheader.end();h++)
      {
          int ds=h->first.size();
          memcpy(hdrData,h->first.c_str(),ds);
	 	  event->headers[hdrn].name=hdrData;
      	  hdrData+=ds;
      	  *(hdrData++)=0;
          ds=h->second.size();
          memcpy(hdrData,h->second.c_str(),ds);
	 	  event->headers[hdrn].value=hdrData;
      	  hdrData+=ds;
      	  *(hdrData++)=0;
		 hdrn++;
      }
	  event->headers[hdrn].name=NULL;
	  event->headers[hdrn].value=NULL;
    
    if (reply2->streaming) {
    	event->size=0;
    }
    else {
		memcpy(event->data, chunk.memory, chunk.size);
		event->size = chunk.size;
    }
    long response_code;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response_code);
    curl_easy_cleanup(curl);
    event->httpStatusCode = response_code;
    
    gevent_EnqueueEvent(reply2->gid, reply2->callback, GHTTP_RESPONSE_EVENT, event, 1, reply2->udata);
  }

  free(chunk.memory);
  curl_slist_free_all(headers); /* free the header list */

  pthread_mutex_lock (&mutexmap);
  map_.erase(reply2->gid);
  pthread_mutex_unlock (&mutexmap);

  return NULL;
}

//######################################################################

extern "C" {
void ghttp_Init()
{
  pthread_mutex_init(&mutexmap, NULL);
  curl_global_init(CURL_GLOBAL_ALL);
}

void ghttp_InitCA(std::string cafolder)
{
	capath=cafolder+"/cacert.pem";
}

void ghttp_Cleanup()
{
  curl_global_cleanup();
  pthread_mutex_destroy(&mutexmap);
}

g_id ghttp_Get(const char* url, const ghttp_Header *header, int streaming, gevent_Callback callback, void* udata)
{
  pthread_t tid;
  int error;
  std::string str;

  g_id gid = g_NextId();     // must be static

  NetworkReply reply2;
  reply2.gid = gid;
  reply2.callback = callback;
  reply2.udata = udata;
  reply2.url = url;
  reply2.data = NULL;
  reply2.size = 0;
  reply2.streaming=streaming;

  reply2.header.push_back("User-Agent: Gideros");
  if (header)
    for (; header->name; ++header){
      str=header->name + colon + header->value;
      reply2.header.push_back(str);
    } 


  pthread_mutex_lock (&mutexmap);
  map_[gid] = reply2;

  //printf("ghttp_Get: %d %p %s\n",gid,&gid,url);

  error = pthread_create(&tid,
			 NULL, /* default attributes please */
			 get_one_url,
			 (void *)&map_[gid]);
  if (0 != error)
    fprintf(stderr, "Couldn't run thread, errno %d\n", error);

  map_[gid].tid=tid;
  pthread_mutex_unlock (&mutexmap);

  return gid;
}

g_id ghttp_Post(const char* url, const ghttp_Header *header, const void* data, size_t size, int streaming, gevent_Callback callback, void* udata)
{

  pthread_t tid;
  int error;
  std::string str;

  g_id gid = g_NextId();

  NetworkReply reply2;
  reply2.gid = gid;
  reply2.callback = callback;
  reply2.udata = udata;
  reply2.url = url;
  reply2.data = malloc(size);
  reply2.size = size;
  reply2.streaming=streaming;

  memcpy(reply2.data,data,size);

  reply2.header.push_back("User-Agent: Gideros");
  if (header)
    for (; header->name; ++header){
      str=header->name + colon + header->value;
      reply2.header.push_back(str);
    } 

  pthread_mutex_lock (&mutexmap);
  map_[gid] = reply2;

  //printf("ghttp_Post: %d %p %s\n",gid,&gid,url);

  error = pthread_create(&tid,
			 NULL, /* default attributes please */
			 post_one,
			 (void *)&map_[gid]);
  if (0 != error)
    fprintf(stderr, "Couldn't run thread, errno %d\n", error);

  map_[gid].tid=tid;
  pthread_mutex_unlock (&mutexmap);

  return gid;
}

g_id ghttp_Delete(const char* url, const ghttp_Header *header, int streaming, gevent_Callback callback, void* udata)
{

  CURL *curl = curl_easy_init();
  curl_easy_setopt(curl, CURLOPT_CAINFO, capath.c_str());
  curl_easy_setopt(curl, CURLOPT_CUSTOMREQUEST, "DELETE");
  curl_easy_setopt(curl, CURLOPT_URL, url);

  struct curl_slist *headers = NULL;

  headers = curl_slist_append(headers, "User-Agent: Gideros");
  if (header)
    for (; header->name; ++header){
      std::string str=header->name + colon + header->value;
      headers = curl_slist_append(headers, str.c_str());
    } 

  curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
  CURLcode ret = curl_easy_perform(curl);
  
  curl_easy_cleanup(curl);
  
  if(ret != CURLE_OK)
    fprintf(stderr, "curl_easy_perform() failed in Delete: %s\n",curl_easy_strerror(ret));
  
	return 0;
}

g_id ghttp_Put(const char* url, const ghttp_Header *header, const void* data, size_t size, int streaming, gevent_Callback callback, void* udata)
{
  pthread_t tid;
  int error;
  std::string str;

  g_id gid = g_NextId();

  //printf("ghttp_Put: size = %d\n",size);

  NetworkReply reply2;
  reply2.gid = gid;
  reply2.callback = callback;
  reply2.udata = udata;
  reply2.url = url;
  reply2.data = malloc(size);
  reply2.size = size;
  reply2.streaming=streaming;

  memcpy(reply2.data,data,size);

  reply2.header.push_back("User-Agent: Gideros");
  if (header)
    for (; header->name; ++header){
      str=header->name + colon + header->value;
      reply2.header.push_back(str);
    } 


  pthread_mutex_lock (&mutexmap);
  map_[gid] = reply2;

  //printf("ghttp_Put: %d %p %s\n",gid,&gid,url);

  error = pthread_create(&tid,
			 NULL, /* default attributes please */
			 put_one_url,
			 (void *)&map_[gid]);
  if (0 != error)
    fprintf(stderr, "Couldn't run thread, errno %d\n", error);

  map_[gid].tid=tid;
  pthread_mutex_unlock (&mutexmap);

  return gid;
}

void ghttp_Close(g_id gid)
{
 pthread_mutex_lock (&mutexmap);
 if (map_.count(gid))
 {
  pthread_cancel(map_[gid].tid);
  map_.erase(gid);
 }
 pthread_mutex_unlock (&mutexmap);
}

void ghttp_CloseAll()
{
  while (!map_.empty())
    ghttp_Close(map_.begin()->second.gid);
}

void ghttp_IgnoreSSLErrors()
{
  sslErrorsIgnore=true;
}

void ghttp_SetProxy(const char *host, int port, const char *user, const char *pass)
{
}


}
