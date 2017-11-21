#include <iostream>
#include <date.h>
#include <chrono>
#include <ctime>
#include <sstream>
#include <signal.h>

#include "spdlog/spdlog.h"

#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <netinet/tcp.h>


#define HOST "haskell-client2.eastus.cloudapp.azure.com"
#define PORT 9002

namespace spd = spdlog;
using namespace std;

typedef chrono::system_clock Clock;

int oldSend(string*);

void setupEndpoint(struct sockaddr_in*);

int sendMessage(string*);

void getHostIp(string*);

void generateEvent(string*);

void my_handler(int );

struct event_t{
    int id = 0;
    struct tm* timestamp = nullptr;
    tuple<int, int> value;
};


int sock;

int main() {
    auto console = spd::stdout_color_mt("console");
    console->info("Starting application");

    /* SIGNAL HANDLING BEGIN */

    struct sigaction sigIntHandler;

    sigIntHandler.sa_handler = my_handler;
    sigemptyset(&sigIntHandler.sa_mask);
    sigIntHandler.sa_flags = 0;

    sigaction(SIGTERM, &sigIntHandler, NULL);

    /* SIGNAL HANDLING END */


//    int sock;
//    int id = 0;
    struct sockaddr_in server;

    setupEndpoint(&server);


    string message;

//    generateEvent(&message);


//    message = "E {id = 7, time = 2017-11-14 18:25:11.6204981 UTC, value = (1,1)}";
//    oldSend(&message);

    console->info("Connect to socket");

    if (connect(sock, (const sockaddr *) &server, sizeof(server)) < 0 ) {
        console->error("Failed to connect to socket");
        exit(-1);
    }
//    generateEvent(&message);

//    send(sock, (char *) message.c_str(), strlen((char *) message.c_str()), 0);


    while(true) {
        generateEvent(&message);
        sendMessage(&message);

        this_thread::sleep_for(chrono::milliseconds(5000));

//        t1.join();
//        message.clear();
//        close(sock);
    }

//    sendMessage(&sock, (const sockaddr*) &server, &message);

    close(sock);
    return 0;
}

int oldSend(string* event) {
    auto console = spd::get("console");
    console->info("Call sendMessage with event: {}", *event);

//    int sock;
    struct sockaddr_in server;
    string inetAddr;

    getHostIp(&inetAddr);
    console->info("Host IP address set to: {}", inetAddr);

    console->info("Create the TCP socket");
    sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        console->info("Could not create socket");
        exit(-1);
    }

    console->info("Setting server struct to empty");
    memset((void*) &server, '\0', sizeof(struct sockaddr_in));

    console->info("Setting up server address information");
    server.sin_family = AF_INET;
    server.sin_port = htons(PORT);
    server.sin_addr.s_addr = inet_addr((char*) inetAddr.c_str());


    console->info("Connect to socket");
    connect(sock, (const sockaddr *) &server, sizeof(server));

    console->info("Send message: {} to socket", *event);
    send(sock, (char *) event->c_str(), strlen((char *) event->c_str()), 0);

    return 0;
}


void setupEndpoint(struct sockaddr_in* server) {
    auto console = spd::get("console");
    console->info("Setting up struct");

    string inetAddr;

    getHostIp(&inetAddr);
    console->info("DNS resolved as: {}", inetAddr);

    console->info("Create the TCP socket");
    sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) {
        console->info("Could not create socket");
        exit(-1);
    }

    console->info("Setting socket TCP_NODELAY");
    int flag = 1;
    if (setsockopt(sock,
                   IPPROTO_TCP,
                   TCP_NODELAY,
                   (char *) &flag,
                   sizeof(int)) < 0)
        console->error("Failed to setsockopt TCP_NODELAY");

    console->info("Setting server struct to empty");
    memset((void *) server, '\0', sizeof(struct sockaddr_in));

    console->info("Setting up server address information");
    server->sin_family = AF_INET;
    server->sin_port = htons(PORT);
    server->sin_addr.s_addr = inet_addr((char*) inetAddr.c_str());
    console->info("Setup complete");
}

int sendMessage(string* event) {
    auto console = spd::get("console");
//    console->info("Call sendMessage with event: {}", *event);

    console->info("Send message: {} to socket", *event);
    send(sock, (char *) event->c_str(), strlen((char *) event->c_str()), 0);

    return 0;
}

// E {id = 1, time = 2017-11-21 14:34:24.670525 UTC, value = (1,1)}
// E {id = 1, time = 2017-11-21 14:34:25.671898 UTC, value = (1,1)}



void generateEvent(string* message) {
//    E {id = 7, time = 2017-11-14 18:25:11.6204981 UTC, value = (1,1)}
    auto console = spd::get("console");
    console->info("Generating event");

    struct event_t e;

    e.id = 1;
    e.value = make_tuple(1,1);

    auto now = Clock::now();
    auto dp = date::floor<date::days>(now);
    auto time = date::make_time(chrono::duration_cast<chrono::microseconds>(now-dp));

    // we cast time to time_t for easy-use in tm struct
    time_t t = Clock::to_time_t(now);
    // cast it back from_time_t, as time_t does not store ms. We can subtract now - from_time_t(t) to find out ms
    // and cast it to the duration we want
//    auto ms = chrono::duration_cast<chrono::milliseconds>(now - Clock::from_time_t(t)).count();
    e.timestamp = gmtime( & t );

    *message = fmt::format("E {{id = {}, time = {}-{}-{} {}:{}:{}.{:06d} {}, value = ({},{})}}\n",
                             e.id,
                             e.timestamp->tm_year + 1900,
                             e.timestamp->tm_mon+1,
                             e.timestamp->tm_mday,
                             e.timestamp->tm_hour,
                             e.timestamp->tm_min,
                             e.timestamp->tm_sec,
                             time.subseconds().count(),
                             e.timestamp->tm_zone,
                             get<0>(e.value),
                             get<1>(e.value)
    );

    // Increment id for next run
//    *id += 1;

    console->info("Event generated: {}", *message);
}


void getHostIp(string* inetAddr) {
    auto console = spd::get("console");

    console->debug("Create variables, set them empty");
    addrinfo hints, *res;
    memset(&hints, 0, sizeof hints);

    console->debug("Set the type of the hints variable");
    hints.ai_family     = AF_UNSPEC;
    hints.ai_socktype   = SOCK_STREAM;
    hints.ai_protocol   = IPPROTO_TCP;

    if (getaddrinfo(HOST, nullptr, &hints, &res) != 0) {
        console->error("We did not getaddrinfo successfully");
        exit(-1);
    }

    inetAddr->assign(inet_ntoa(((sockaddr_in *) res -> ai_addr) -> sin_addr));
    console->debug("Successfully set inetAddr:{}", *inetAddr);
}

void my_handler(int s){
    auto console = spd::get("console");
    console->info("Caught signal {}", s);

    console->info("Closing sock {}", sock);
    close(sock);

    exit(s);
}
