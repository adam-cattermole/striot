package com.adam.striot;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.Queue;


/**
 * Created by Adam Cattermole on 01/06/2018.
 */
public class TCPConsumer implements Runnable  {

    private final static Logger logger = LoggerFactory.getLogger(TCPConsumer.class);

    private Queue<String> buffer;

    public TCPConsumer(Queue<String> buffer) {
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
            while ((inputLine = in.readLine()) != null) {
//                logger.info(inputLine);
                this.buffer.offer(inputLine);
            }

            in.close();
            clientSocket.close();
            serverSocket.close();

            logger.info("Connected closed...");

        } catch (IOException e) {
            logger.error("Exception caught when trying to listen on port 9001 or listening for a connection");
            logger.error(e.getMessage());
        }
    }


}
