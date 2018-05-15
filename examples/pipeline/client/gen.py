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
RATE = 10000

CONN_CNT = [5, 6, 7, 8]

USERNAME = "azure"
RESULTS_HOST = os.environ["HASKELL_SERVER_SERVICE_HOST"]
LOG_PATH = "/home/azure/striot/examples/pipeline/server/sw-log.txt"

RATES = [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]

HOSTNAME = "{}:9001".format(os.environ["HASKELL_CLIENT2_SERVICE_HOST"])

logging.basicConfig(level=logging.INFO,
                    format='(%(threadName)-10s)[%(levelname)-8s] '
                    '%(asctime)s.%(msecs)-3d %(message)s',
                    datefmt='%X')


def main():
    logging.info("Start")
    client = paramiko.SSHClient()
    client.load_system_host_keys()
    client.set_missing_host_key_policy(paramiko.WarningPolicy())
    client.connect(hostname=RESULTS_HOST, username=USERNAME)
    sftp = client.open_sftp()
    f = sftp.open(LOG_PATH, 'r')
    for i in range(1, ITERATIONS+1):
        logging.info("Iteration {}:".format(i))
        currdir = "iter{}".format(i)
        if not os.path.exists(currdir):
            os.makedirs(currdir)
        with open("{}/serial-log.txt".format(currdir), 'wb') as log_file:
            run_iteration(i, currdir, log_file, f, client)
    f.close()
    sftp.close()
    client.close()
    if len(sys.argv) == 1:
        exit(0)
    else:
        time.sleep(sys.argv[1])


def run_iteration(currdir, log_file, sftp_file, ssh_client=None):
    for rate in RATES:
        f_name = "{}/tcpkali_r{}.txt".format(currdir, rate)
        runner = TCPKaliRunner(rate, f_name)
        runner.run()
        time.sleep(30)
        log_file.write(sftp_file.read())


def run_iteration_conn(currdir, log_file, sftp_file, ssh_client=None):
    for conn in CONN_CNT:
        f_name = "{}/tcpkali_r{}_c{}.txt".format(currdir, RATE, conn)
        runner = TCPKaliRunner(RATE, f_name, conn)
        runner.run()
        time.sleep(30)
        log_file.write(sftp_file.read())


class TCPKaliRunner():

    def __init__(self, rate, file, conn=1):
        self.rate = rate
        self.file = file
        self.conn = conn

    def run(self):
        logging.info('Running with rate {}hz, c{}'.format(self.rate,
                                                          self.conn))
        with open(self.file, 'w') as open_file:
            subprocess.run(["tcpkali", "-em",
                            self.event(EVENT_TYPE_AESON, id=self.rate),
                            "-c{}".format(self.conn),
                            "-r{}".format(self.rate),
                            "--dump-all",
                            "--nagle=off",
                            "--write-combine=off",
                            "-T{}s".format(TEST_LENGTH),
                            HOSTNAME],
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
