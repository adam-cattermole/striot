package com.adam.striot;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Queue;
import java.util.concurrent.ConcurrentLinkedQueue;

/**
 * Created by Adam Cattermole on 01/06/2018.
 */

public class Runner {

    public static final String AMQ_BROKER = "AMQ_DEFAULT_SERVICE_HOST";

    final static Logger logger = LoggerFactory.getLogger(Runner.class);

    public static void main(String[] args) {
        logger.info("Started gen broker...");
        String amqBrokerHost = System.getenv(AMQ_BROKER);
        if (amqBrokerHost == null) {
            logger.error("AMQ_DEFAULT_SERVICE_HOST not set, exiting...");
            System.exit(1);
        }
        logger.debug("Broker at {}...", amqBrokerHost);

        Queue<String> buffer = new ConcurrentLinkedQueue<>();

        Thread producer = new Thread(new AMQProducer(amqBrokerHost, buffer));
        producer.start();

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
