package com.adam.striot;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;


import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.LinkedBlockingQueue;

/**
 * Created by Adam Cattermole on 01/06/2018.
 */

public class Runner {

    public static final String AMQ_BROKER = "AMQ_BROKER_SERVICE_HOST";

    public static final int NUM_PRODUCERS = 5;

    final static Logger logger = LoggerFactory.getLogger(Runner.class);

    public static void main(String[] args) {
        logger.info("Started gen broker...");
        String amqBrokerHost = System.getenv(AMQ_BROKER);
        if (amqBrokerHost == null) {
            logger.error(String.format("%s not set, exiting...", AMQ_BROKER));
            System.exit(1);
        }
        logger.debug("Broker at {}...", amqBrokerHost);

        LinkedBlockingQueue<String> buffer = new LinkedBlockingQueue<>(500000);


        Thread infoLogger = new Thread(new InfoLogger(buffer));
        infoLogger.start();

        List<Thread> producers = new ArrayList<>(NUM_PRODUCERS);

            for (int i = 0; i < NUM_PRODUCERS; i++) {
            producers.add(new Thread(new AMQProducer(amqBrokerHost, buffer)));
        }

        for (Thread prod : producers) {
            prod.start();
        }

        Thread consumer = new Thread(new TCPConsumer(buffer));
        consumer.start();

        try {
//            consumer.join();
            Thread.sleep(100000000);
        } catch (InterruptedException e) {
            e.printStackTrace();
        }

//        try {
//            Thread.sleep(1000000000L);
//        } catch (InterruptedException e) {
//            e.printStackTrace();
//        }

    }
}
