package com.adam.striot;

import org.apache.activemq.ActiveMQConnectionFactory;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.jms.*;

import java.util.Queue;


/**
 * Created by Adam Cattermole on 01/06/2018.
 */
public class AMQProducer implements Runnable {

    private final static Logger logger = LoggerFactory.getLogger(AMQProducer.class);

    private String host;
    private Queue<String> buffer;


    public AMQProducer(String host, Queue<String> buffer) {
        this.host = host;
        this.buffer = buffer;
    }

    public void run() {
        try {
            ActiveMQConnectionFactory connectionFactory = new ActiveMQConnectionFactory("admin","yy^U#Fca!52Y", String.format("tcp://%s:61616", this.host));
            //?jms.prefetchPolicy.queuePrefetch=25000

            Connection connection = connectionFactory.createConnection();

            connection.start();

            Session session = connection.createSession(false, Session.AUTO_ACKNOWLEDGE);

            Destination destination = session.createQueue("SampleQueue");

            MessageProducer producer = session.createProducer(destination);
            producer.setDisableMessageID(true);
            producer.setDisableMessageTimestamp(true);
            producer.setDeliveryMode(DeliveryMode.NON_PERSISTENT);

            logger.info("Connected to broker...");

            while (true) {
                if (!this.buffer.isEmpty()) {
                    String out = this.buffer.poll();
//                    logger.info("Writing message: {}", out);
//                    TextMessage message = session.createTextMessage(out);
                    producer.send(session.createTextMessage(out));
                }
            }

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

}
