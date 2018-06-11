# from threading import Thread
import time
import subprocess
import logging
import paramiko
import os
import sys

EVENT_TYPE_NORMAL = 0
EVENT_TYPE_AESON = 1

ITERATIONS = 5
TEST_LENGTH = 30
RATE = 1

USERNAME = "azure"
# RESULTS_HOST = os.environ["HASKELL_SERVER_SERVICE_HOST"]
LOG_PATH = "/home/azure/striot/examples/pipeline/server/sw-log.txt"

RATES = [25000, 30000, 35000, 40000]
# RATES = [1, 5]

# HOSTNAME = "127.0.0.1:9002"
HOSTNAME = "{}:9001".format(os.environ["HASKELL_GEN_BROKER_SERVICE_HOST"])

logging.basicConfig(level=logging.INFO,
                    format='(%(threadName)-10s)[%(levelname)-8s] '
                    '%(asctime)s.%(msecs)-3d %(message)s',
                    datefmt='%X')


def main():
    logging.info("Start")
    # client = paramiko.SSHClient()
    # client.load_system_host_keys()
    # client.set_missing_host_key_policy(paramiko.WarningPolicy())
    # client.connect(hostname=RESULTS_HOST, username=USERNAME)
    # sftp = client.open_sftp()
    # f = sftp.open(LOG_PATH, 'r')
    for i in range(1, ITERATIONS+1):
        logging.info("Iteration {}:".format(i))
        currdir = "iter{}".format(i)
        if not os.path.exists(currdir):
            os.makedirs(currdir)
        with open("{}/serial-log.txt".format(currdir), 'wb') as log_file:
            run_iteration(i, currdir, log_file)

    time.sleep(100000000)
    # f.close()
    # sftp.close()
    # client.close()
    if len(sys.argv) == 1:
        exit(0)
    else:
        time.sleep(sys.argv[1])


def run_iteration(iteration, currdir, log_file, sftp_f=None, ssh_client=None):
    for rate in RATES:
        f_name = "{}/tcpkali_r{}.txt".format(currdir, rate)
        runner = TCPKaliRunner(rate, f_name)
        runner.run()
        time.sleep(30)
        if (sftp_f):
            log_file.write(sftp_f.read())

    # stats = sftp.stat(LOG_PATH)
    # sftp.get(LOG_PATH,
    #          "{}/serial-log.txt".format(currdir))
    # sftp.remove(LOG_PATH)
    # sftp.close()


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
