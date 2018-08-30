package com.adam.striot;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.concurrent.LinkedBlockingQueue;



/**
 * Created by Adam Cattermole on 01/06/2018.
 */
public class TCPConsumer implements Runnable  {

    private final static Logger logger = LoggerFactory.getLogger(TCPConsumer.class);

    private LinkedBlockingQueue<String> buffer;

    public TCPConsumer(LinkedBlockingQueue<String> buffer) {
        this.buffer = buffer;
    }


    public void run() {
        while (true) {
            receive();
        }
    }


    public void receive() {
        try (
                ServerSocket serverSocket =
                        new ServerSocket(9001);
                Socket clientSocket = serverSocket.accept();
                BufferedReader in = new BufferedReader(
                        new InputStreamReader(clientSocket.getInputStream()));
        ) {
            logger.info("Connected to gen...");

            String inputLine;
            try {
                while ((inputLine = in.readLine()) != null) {
//                logger.info(inputLine);
                    this.buffer.put(inputLine);
                }
            } catch (InterruptedException e) {
                e.printStackTrace();
                System.exit(1);
            }

            in.close();
            clientSocket.close();
            serverSocket.close();

            logger.info("Connection closed...");

        } catch (IOException e) {
            logger.error("Exception caught when trying to listen on port 9001 or listening for a connection");
            logger.error(e.getMessage());
        }
    }


}
