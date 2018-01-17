# from threading import Thread
import time
import subprocess
import logging
import paramiko
import os

ITERATIONS = 5
TEST_LENGTH = 30
RATE = 1

# USERNAME = "azure"
RESULTS_HOST = os.environ["HASKELL_SERVER_SERVICE_HOST"]
LOG_PATH = "/opt/server/sw-log.txt"

RATES = [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10000]
# RATES = [1, 5]

# HOSTNAME = "127.0.0.1:9002"
HOSTNAME = "{}:9002".format(os.environ["HASKELL_CLIENT2_SERVICE_HOST"])

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
    client = None
    for i in range(1, ITERATIONS+1):
        logging.info("Iteration {}:".format(i))
        run_iteration(client, i)
    # client.close()
    time.sleep(60)




def run_iteration(ssh_client, iteration):
    currdir = "iter{}".format(iteration)
    if not os.path.exists(currdir):
        os.makedirs(currdir)
    for rate in RATES:
        f_name = "{}/tcpkali_r{}.txt".format(currdir, rate)
        runner = TCPKaliRunner(rate, f_name)
        runner.run()
    # sftp = ssh_client.open_sftp()
    # sftp.get(LOG_PATH,
             # "{}/serial-log.txt".format(currdir))
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
                            "E {{id = {}, ".format(self.rate) +
                            "time = 2017-11-21 16:30:00.000000 UTC, "
                            "value = \"\{message.marker}\"}\n",
                            "-r{}".format(self.rate),
                            "--dump-all",
                            "--nagle=off",
                            "--write-combine=off",
                            "-T{}s".format(TEST_LENGTH),
                            HOSTNAME],
                           stderr=open_file,
                           stdout=open_file)

# tcpkali -em "E {id = 0, time = 2017-11-21 16:30:00.000000 UTC, value = (1,1)}\n" -r 1 --dump-all haskell-client2.eastus.cloudapp.azure.com:9002


if __name__ == '__main__':
    main()
