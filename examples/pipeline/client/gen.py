# from threading import Thread
import time
import subprocess
import logging
import paramiko
import os
import sys

EVENT_TYPE_NORMAL = 0
EVENT_TYPE_AESON = 1

ITERATIONS = 3
TEST_LENGTH = 30
RATE = 1

USERNAME = "azure"
LOG_PATH = "/home/azure/sw-log.txt"

RATES = [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]
# RATES = [1, 5]

# HOSTNAME = "127.0.0.1:9002"
SERVER_HOST = os.environ["HASKELL_SERVER_SERVICE_HOST"]
CLIENT2_HOST = os.environ["HASKELL_CLIENT2_SERVICE_HOST"]

logging.basicConfig(level=logging.INFO,
                    format='(%(threadName)-10s)[%(levelname)-8s] '
                    '%(asctime)s.%(msecs)-3d %(message)s',
                    datefmt='%X')

SERVER = 0
CLIENT2 = 1


def main():
    logging.info("Start")

    clients = []
    clients[SERVER] = create_client()
    clients[CLIENT2] = create_client()

    for i in range(1, ITERATIONS+1):
        logging.info("Iteration {}:".format(i))
        run_iteration(i, clients)

    if len(sys.argv) == 1:
        exit(0)
    else:
        time.sleep(sys.argv[1])


def run_iteration(iteration, clients, pos):
    currdir = "iter{}".format(iteration)
    if not os.path.exists(currdir):
        os.makedirs(currdir)
    # sftp = ssh_client.open_sftp()
    # f = sftp.open(LOG_PATH, 'r')
    # f.seek(pos)
    # with open("{}/serial-log.txt".format(currdir), 'wb') as log_file:
    # client.connect(hostname=RESULTS_HOST, username=USERNAME)
    for rate in RATES:
        clients[SERVER].connect(hostname=SERVER_HOST, username=USERNAME)
        clients[SERVER].exec_command(
            './striot/examples/pipeline/server/server +RTS -N -qg')
        clients[CLIENT2].connect(hostname=CLIENT2_HOST, username=USERNAME)
        clients[CLIENT2].exec_command(
            './striot/examples/pipeline/client2/client2 +RTS -N -qg')
        tcpkf_name = "{}/tcpkali_r{}.txt".format(currdir, rate)
        runner = TCPKaliRunner(rate, tcpkf_name)
        runner.run()
        time.sleep(30)
        sftp = clients[SERVER].open_sftp()
        sftp.get(LOG_PATH, "{}/serial-log_r{}.txt".format(currdir, rate))
        sftp.close()
        clients[SERVER].close()
        clients[CLIENT2].close()


def create_client():
    client = paramiko.SSHClient()
    client.load_system_host_keys()
    client.set_missing_host_key_policy(paramiko.WarningPolicy())
    # client.connect(hostname=hostname, username=username)
    return client


class TCPKaliRunner():

    def __init__(self, rate, file):
        self.rate = rate
        self.file = file

    def run(self):
        logging.info('Running with rate {}hz'.format(self.rate))
        with open(self.file, 'w') as open_file:
            subprocess.run(["tcpkali", "-em",
                            self.event(EVENT_TYPE_AESON, id=self.rate),
                            "-r{}".format(self.rate),
                            # "--dump-all",
                            "--nagle=off",
                            "--write-combine=off",
                            "-T{}s".format(TEST_LENGTH),
                            "{}:9001".format(CLIENT2_HOST)],
                           stderr=open_file,
                           stdout=open_file)

    def event(self, type, id):
        if type == EVENT_TYPE_NORMAL:
            return ("E {{id = {}, ".format(id) +
                    "time = 2017-11-21 16:30:00.000000 UTC, " +
                    "value = \"\{message.marker}\"}\n")
        elif type == EVENT_TYPE_AESON:
            return ("{\"tag\":\"E\"," +
                    "\"id\":{},".format(id) +
                    "\"time\":\"2017-11-21T16:30:00.000000Z\"," +
                    "\"value\":\"\{message.marker}\"}\n")
        else:
            return ""


if __name__ == '__main__':
    main()
